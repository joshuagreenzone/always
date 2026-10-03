
<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

function respond(int $status, array $payload): void
{
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

try {
    $input = json_decode(file_get_contents("php://input"), true) ?? [];

    $accId = (int)($input["accId"] ?? 0);
    $bottleNumbers = $input["bottleNumbers"] ?? [];

    $latitude = isset($input["latitude"])
        ? (float)$input["latitude"]
        : null;

    $longitude = isset($input["longitude"])
        ? (float)$input["longitude"]
        : null;

    $accuracy = isset($input["accuracy"])
        ? (float)$input["accuracy"]
        : null;

    if (
        $accId <= 0 ||
        !is_array($bottleNumbers) ||
        count($bottleNumbers) === 0
    ) {
        respond(400, [
            "success" => false,
            "message" => "Account ID and at least one bottle are required."
        ]);
    }

    $bottleNumbers = array_values(array_unique(array_map(
        fn($number) => trim((string)$number),
        $bottleNumbers
    )));

    if (in_array("", $bottleNumbers, true)) {
        respond(400, [
            "success" => false,
            "message" => "The batch contains an empty bottle number."
        ]);
    }

    if (count($bottleNumbers) > 200) {
        respond(400, [
            "success" => false,
            "message" => "A batch cannot contain more than 200 bottles."
        ]);
    }

    if (
        $latitude === null ||
        $longitude === null ||
        $accuracy === null
    ) {
        respond(400, [
            "success" => false,
            "message" => "GPS location information is required."
        ]);
    }

    $database = new Database();
    $db = $database->connect();

    // Validate account.
    $stmt = $db->prepare("
        SELECT AccID, AccType
        FROM accounts
        WHERE AccID = :accId
        LIMIT 1
    ");

    $stmt->execute([
        ":accId" => $accId
    ]);

    $account = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$account) {
        respond(403, [
            "success" => false,
            "message" => "Invalid account."
        ]);
    }

    $db->beginTransaction();

    try {
        $saved = [];

        foreach ($bottleNumbers as $bottleNumber) {
            // Lock the bottle record during validation and saving.
            $stmt = $db->prepare("
                SELECT
                    b.BottleID,
                    b.BottleNumber,
                    b.BottleTypeID,
                    bt.BottleType,
                    bt.Price
                FROM bottles b
                INNER JOIN bottle_types bt
                    ON bt.BottleTypeID = b.BottleTypeID
                WHERE b.BottleNumber = :bottleNumber
                LIMIT 1
                FOR UPDATE
            ");

            $stmt->execute([
                ":bottleNumber" => $bottleNumber
            ]);

            $bottle = $stmt->fetch(PDO::FETCH_ASSOC);

            if (!$bottle) {
                throw new DomainException(
                    "Bottle {$bottleNumber} was not found. No records were saved."
                );
            }

            $bottleId = (int)$bottle["BottleID"];

            // Get latest refill.
            $stmt = $db->prepare("
                SELECT RefillID, RefillDateTime
                FROM refill
                WHERE BottleID = :bottleId
                ORDER BY RefillDateTime DESC, RefillID DESC
                LIMIT 1
            ");

            $stmt->execute([
                ":bottleId" => $bottleId
            ]);

            $latestRefill = $stmt->fetch(PDO::FETCH_ASSOC);

            // Get latest premise movement.
            $stmt = $db->prepare("
                SELECT MovementID, MovementType, MovementDateTime
                FROM premise_bottle_movement
                WHERE BottleID = :bottleId
                ORDER BY MovementDateTime DESC, MovementID DESC
                LIMIT 1
            ");

            $stmt->execute([
                ":bottleId" => $bottleId
            ]);

            $latestMovement = $stmt->fetch(PDO::FETCH_ASSOC);

            // Get latest bottle scan event.
            $stmt = $db->prepare("
                SELECT EventType, ScanDateTime
                FROM bottle_scan_event
                WHERE BottleID = :bottleId
                ORDER BY ScanDateTime DESC
                LIMIT 1
            ");

            $stmt->execute([
                ":bottleId" => $bottleId
            ]);

            $latestScanEvent = $stmt->fetch(PDO::FETCH_ASSOC);

            /*
             * Allow if:
             * - Latest premise movement is RETURN; OR
             * - Latest bottle scan event is PICKUP_SCAN.
             */
            $allowedByMovement =
                $latestMovement &&
                strtoupper(trim($latestMovement["MovementType"])) === "RETURN";

            $allowedByPickupScan =
                $latestScanEvent &&
                strtoupper(trim($latestScanEvent["EventType"])) === "PICKUP_SCAN";

            /*
             * No movement and no pickup scan:
             * permit a first refill only for a genuinely new bottle.
             */
            if (!$latestMovement && !$allowedByPickupScan) {
                $stmt = $db->prepare("
                    SELECT COUNT(*)
                    FROM order_delivery_transaction
                    WHERE BottleID = :bottleId
                ");

                $stmt->execute([
                    ":bottleId" => $bottleId
                ]);

                $deliveryCount = (int)$stmt->fetchColumn();

                if ($latestRefill || $deliveryCount > 0) {
                    throw new DomainException(
                        "Bottle {$bottleNumber} has previous activity but no "
                        . "premise movement history or valid pickup scan. "
                        . "No records were saved."
                    );
                }
            } elseif (!$allowedByMovement && !$allowedByPickupScan) {
                throw new DomainException(
                    "Bottle {$bottleNumber} is not eligible for refill. "
                    . "Its latest premise movement is not RETURN and "
                    . "its latest scan event is not PICKUP_SCAN. "
                    . "No records were saved."
                );
            }

            // Prevent duplicate refill after the latest RETURN movement.
            if (
                $allowedByMovement &&
                $latestRefill &&
                strtotime($latestRefill["RefillDateTime"]) >=
                strtotime($latestMovement["MovementDateTime"])
            ) {
                throw new DomainException(
                    "Bottle {$bottleNumber} has already been refilled "
                    . "after its latest return. No records were saved."
                );
            }

            /*
             * If eligibility is based on PICKUP_SCAN, prevent a duplicate
             * refill after that scan.
             */
            if (
                !$allowedByMovement &&
                $allowedByPickupScan &&
                $latestRefill &&
                strtotime($latestRefill["RefillDateTime"]) >=
                strtotime($latestScanEvent["ScanDateTime"])
            ) {
                throw new DomainException(
                    "Bottle {$bottleNumber} has already been refilled "
                    . "after its latest pickup scan. No records were saved."
                );
            }

            // Save refill.
            $stmt = $db->prepare("
                INSERT INTO refill (
                    BottleID,
                    RefillDateTime
                )
                VALUES (
                    :bottleId,
                    CURRENT_TIMESTAMP
                )
            ");

            $stmt->execute([
                ":bottleId" => $bottleId
            ]);

            $refillId = (int)$db->lastInsertId();

            // Save refill audit event.
            $stmt = $db->prepare("
                INSERT INTO bottle_scan_event (
                    BottleID,
                    AccID,
                    EventType,
                    RefillID,
                    ScanDateTime,
                    Latitude,
                    Longitude,
                    LocationAccuracy
                )
                VALUES (
                    :bottleId,
                    :accId,
                    'REFILL_SCAN',
                    :refillId,
                    CURRENT_TIMESTAMP,
                    :latitude,
                    :longitude,
                    :accuracy
                )
            ");

            $stmt->execute([
                ":bottleId" => $bottleId,
                ":accId" => $accId,
                ":refillId" => $refillId,
                ":latitude" => $latitude,
                ":longitude" => $longitude,
                ":accuracy" => $accuracy
            ]);

            $saved[] = [
                "RefillID" => $refillId,
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle["BottleNumber"],
                "BottleTypeID" => (int)$bottle["BottleTypeID"],
                "BottleType" => $bottle["BottleType"],
                "Price" => (float)$bottle["Price"]
            ];
        }

        // Save the batch only when every bottle passes validation.
        $db->commit();

        respond(200, [
            "success" => true,
            "message" => "Successfully saved " . count($saved) . " refill(s).",
            "data" => [
                "count" => count($saved),
                "refills" => $saved
            ]
        ]);

    } catch (DomainException $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }

        respond(409, [
            "success" => false,
            "message" => $e->getMessage()
        ]);

    } catch (Throwable $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }

        throw $e;
    }

} catch (PDOException $e) {
    error_log("Refill batch database error: " . $e->getMessage());

    respond(500, [
        "success" => false,
        "message" => "Database error while saving refill batch."
    ]);

} catch (Throwable $e) {
    error_log("Refill batch error: " . $e->getMessage());

    respond(500, [
        "success" => false,
        "message" => "Unable to save refill batch."
    ]);
}
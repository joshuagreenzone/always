
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
    $bottleNumber = trim($_GET["bottleNumber"] ?? "");

    if ($bottleNumber === "") {
        respond(400, [
            "success" => false,
            "message" => "Bottle number is required."
        ]);
    }

    $database = new Database();
    $db = $database->connect();

    // Find registered bottle.
    $stmt = $db->prepare("
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            b.BottleRegDateTime,
            bt.BottleType,
            bt.Price
        FROM bottles b
        INNER JOIN bottle_types bt
            ON bt.BottleTypeID = b.BottleTypeID
        WHERE b.BottleNumber = :bottleNumber
        LIMIT 1
    ");

    $stmt->execute([
        ":bottleNumber" => $bottleNumber
    ]);

    $bottle = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$bottle) {
        respond(404, [
            "success" => false,
            "message" => "Invalid bottle. This bottle is not registered."
        ]);
    }

    $bottleId = (int)$bottle["BottleID"];

    // Get the latest refill.
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

    // Get the latest premise movement.
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

    // Get the latest bottle scan event.
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
     * Eligibility rule:
     * 1. Latest premise movement is RETURN; OR
     * 2. Latest bottle scan event is PICKUP_SCAN.
     */
    $allowedByMovement =
        $latestMovement &&
        strtoupper(trim($latestMovement["MovementType"])) === "RETURN";

    $allowedByPickupScan =
        $latestScanEvent &&
        strtoupper(trim($latestScanEvent["EventType"])) === "PICKUP_SCAN";

    /*
     * No movement history and no pickup scan:
     * Allow a first refill only for a genuinely new bottle.
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
            respond(409, [
                "success" => false,
                "message" =>
                    "This bottle has previous activity but no premise movement history or valid pickup scan. Please verify its records."
            ]);
        }

        respond(200, [
            "success" => true,
            "message" => "New bottle is eligible for its first refill.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle["BottleNumber"],
                "BottleTypeID" => (int)$bottle["BottleTypeID"],
                "BottleType" => $bottle["BottleType"],
                "Price" => (float)$bottle["Price"],
                "BottleRegDateTime" => $bottle["BottleRegDateTime"]
            ]
        ]);
    }

    /*
     * A bottle with history must satisfy at least one of the two
     * eligibility conditions.
     */
    if (!$allowedByMovement && !$allowedByPickupScan) {
        respond(409, [
            "success" => false,
            "message" =>
                "Bottle is not eligible for refill. Its latest premise movement is not RETURN and its latest scan event is not PICKUP_SCAN.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle["BottleNumber"],
                "MovementType" => $latestMovement["MovementType"] ?? null,
                "EventType" => $latestScanEvent["EventType"] ?? null
            ]
        ]);
    }

    /*
     * Prevent duplicate refills during the same RETURN cycle.
     */
    if (
        $allowedByMovement &&
        $latestRefill &&
        strtotime($latestRefill["RefillDateTime"]) >=
        strtotime($latestMovement["MovementDateTime"])
    ) {
        respond(409, [
            "success" => false,
            "message" =>
                "This bottle has already been refilled after its latest return.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle["BottleNumber"],
                "RefillID" => $latestRefill["RefillID"],
                "RefillDateTime" => $latestRefill["RefillDateTime"]
            ]
        ]);
    }

    /*
     * If eligibility comes from PICKUP_SCAN rather than RETURN,
     * prevent another refill after that pickup scan.
     */
    if (
        !$allowedByMovement &&
        $allowedByPickupScan &&
        $latestRefill &&
        strtotime($latestRefill["RefillDateTime"]) >=
        strtotime($latestScanEvent["ScanDateTime"])
    ) {
        respond(409, [
            "success" => false,
            "message" =>
                "This bottle has already been refilled after its latest pickup scan.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle["BottleNumber"],
                "RefillID" => $latestRefill["RefillID"],
                "RefillDateTime" => $latestRefill["RefillDateTime"]
            ]
        ]);
    }

    respond(200, [
        "success" => true,
        "message" => "Bottle is eligible for refill.",
        "data" => [
            "BottleID" => $bottleId,
            "BottleNumber" => $bottle["BottleNumber"],
            "BottleTypeID" => (int)$bottle["BottleTypeID"],
            "BottleType" => $bottle["BottleType"],
            "Price" => (float)$bottle["Price"],
            "BottleRegDateTime" => $bottle["BottleRegDateTime"]
        ]
    ]);

} catch (PDOException $e) {
    error_log("Refill bottle verification database error: " . $e->getMessage());

    respond(500, [
        "success" => false,
        "message" => "Database error while verifying bottle."
    ]);

} catch (Throwable $e) {
    error_log("Refill bottle verification error: " . $e->getMessage());

    respond(500, [
        "success" => false,
        "message" => "Unable to verify bottle."
    ]);
}
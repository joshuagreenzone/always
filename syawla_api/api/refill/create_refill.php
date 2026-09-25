<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $input = json_decode(file_get_contents("php://input"), true);

    $accId = (int) ($input['accId'] ?? 0);
    $bottleNumber = trim($input['bottleNumber'] ?? '');

    $latitude = isset($input['latitude'])
        ? (float) $input['latitude']
        : null;

    $longitude = isset($input['longitude'])
        ? (float) $input['longitude']
        : null;

    $accuracy = isset($input['accuracy'])
        ? (float) $input['accuracy']
        : null;


    /*
     * ---------------------------------------------------------
     * 1. VALIDATE INPUT
     * ---------------------------------------------------------
     */

    if ($accId <= 0) {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" => "Account ID is required."
        ]);

        exit;
    }

    if ($bottleNumber === '') {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" => "Bottle number is required."
        ]);

        exit;
    }

    if (
        $latitude === null ||
        $longitude === null ||
        $accuracy === null
    ) {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" =>
                "Location information is required. Please enable GPS and try again."
        ]);

        exit;
    }


    /*
     * ---------------------------------------------------------
     * 2. CONNECT TO DATABASE
     * ---------------------------------------------------------
     */

    $database = new Database();
    $db = $database->connect();


    /*
     * ---------------------------------------------------------
     * 3. VERIFY ACCOUNT
     * ---------------------------------------------------------
     */

    $accountSql = "
        SELECT
            AccID,
            AccType

        FROM accounts

        WHERE AccID = :accId

        LIMIT 1
    ";

    $accountStmt = $db->prepare($accountSql);

    $accountStmt->execute([
        ':accId' => $accId
    ]);

    $account = $accountStmt->fetch();

    if (!$account) {

        http_response_code(403);

        echo json_encode([
            "success" => false,
            "message" => "Invalid account."
        ]);

        exit;
    }


    /*
     * ---------------------------------------------------------
     * 4. FIND THE BOTTLE
     * ---------------------------------------------------------
     */

    $sql = "
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            bt.BottleType,
            bt.Price

        FROM bottles b

        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID

        WHERE b.BottleNumber = :bottleNumber

        LIMIT 1
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':bottleNumber' => $bottleNumber
    ]);

    $bottle = $stmt->fetch();

    if (!$bottle) {

        http_response_code(404);

        echo json_encode([
            "success" => false,
            "message" => "Bottle not found."
        ]);

        exit;
    }

    $bottleId = (int) $bottle['BottleID'];


    /*
     * ---------------------------------------------------------
     * 5. FIND THE MOST RECENT REFILL
     * ---------------------------------------------------------
     */

    $latestRefillSql = "
        SELECT
            RefillID,
            RefillDateTime

        FROM refill

        WHERE BottleID = :bottleId

        ORDER BY RefillDateTime DESC, RefillID DESC

        LIMIT 1
    ";

    $latestRefillStmt = $db->prepare($latestRefillSql);

    $latestRefillStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestRefill = $latestRefillStmt->fetch();


    /*
     * ---------------------------------------------------------
     * 6. FIND THE MOST RECENT PICKUP
     * ---------------------------------------------------------
     */

    $latestPickupSql = "
        SELECT
            p.PickUpID,
            p.PickUpDateTime,
            p.DeliveryID

        FROM delivery_pickup_transaction dpt

        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID

        WHERE dpt.BottleID = :bottleId

        ORDER BY p.PickUpDateTime DESC, p.PickUpID DESC

        LIMIT 1
    ";

    $latestPickupStmt = $db->prepare($latestPickupSql);

    $latestPickupStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestPickup = $latestPickupStmt->fetch();


    /*
     * ---------------------------------------------------------
     * 7. BOTTLE MUST HAVE BEEN PICKED UP
     * ---------------------------------------------------------
     */

    if (!$latestPickup) {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" =>
                "This bottle has not been picked up yet. Only picked-up bottles can be refilled."
        ]);

        exit;
    }


    /*
     * ---------------------------------------------------------
     * 8. CHECK WHETHER ALREADY REFILLED
     *    AFTER MOST RECENT PICKUP
     * ---------------------------------------------------------
     */

    if (
        $latestRefill &&
        strtotime($latestRefill['RefillDateTime']) >=
        strtotime($latestPickup['PickUpDateTime'])
    ) {

        http_response_code(409);

        echo json_encode([
            "success" => false,
            "message" =>
                "This bottle has already been refilled after its latest pickup.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle['BottleNumber'],
                "RefillID" => $latestRefill['RefillID'],
                "RefillDateTime" => $latestRefill['RefillDateTime'],
                "PickUpID" => $latestPickup['PickUpID'],
                "PickUpDateTime" => $latestPickup['PickUpDateTime']
            ]
        ]);

        exit;
    }


    /*
     * ---------------------------------------------------------
     * 9. SAFETY CHECK
     * ---------------------------------------------------------
     *
     * Make sure the bottle has not already been processed
     * for another delivery after its latest pickup.
     */

    $deliverySql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID,
            d.DeliveryStatus,
            d.DeliveryDateTime

        FROM order_delivery_transaction odt

        INNER JOIN delivery d
            ON odt.DeliveryID = d.DeliveryID

        WHERE odt.BottleID = :bottleId

          AND d.DeliveryDateTime >
              :pickupDateTime

        ORDER BY d.DeliveryDateTime DESC,
                 odt.ODTID DESC

        LIMIT 1
    ";

    $deliveryStmt = $db->prepare($deliverySql);

    $deliveryStmt->execute([
        ':bottleId' => $bottleId,
        ':pickupDateTime' => $latestPickup['PickUpDateTime']
    ]);

    $delivery = $deliveryStmt->fetch();

    if ($delivery) {

        http_response_code(409);

        echo json_encode([
            "success" => false,
            "message" =>
                "This bottle has already been processed for delivery and cannot be refilled at this time.",
            "data" => [
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle['BottleNumber'],
                "DeliveryID" => $delivery['DeliveryID'],
                "DeliveryStatus" => $delivery['DeliveryStatus'],
                "DeliveryDateTime" => $delivery['DeliveryDateTime']
            ]
        ]);

        exit;
    }


    /*
     * ---------------------------------------------------------
     * 10. CREATE REFILL + SCAN EVENT
     * ---------------------------------------------------------
     *
     * Both records are created in one transaction.
     *
     * If either insert fails, neither record is saved.
     */

    $db->beginTransaction();

    try {

        /*
         * Create refill record.
         */

        $insertSql = "
            INSERT INTO refill
            (
                BottleID,
                RefillDateTime
            )
            VALUES
            (
                :bottleId,
                CURRENT_TIMESTAMP
            )
        ";

        $insertStmt = $db->prepare($insertSql);

        $insertStmt->execute([
            ':bottleId' => $bottleId
        ]);

        $refillId = (int) $db->lastInsertId();


        /*
         * Create immutable bottle scan audit record.
         */

        $scanSql = "
            INSERT INTO bottle_scan_event
            (
                BottleID,
                AccID,
                EventType,
                RefillID,
                ScanDateTime,
                Latitude,
                Longitude,
                LocationAccuracy
            )
            VALUES
            (
                :bottleId,
                :accId,
                'REFILL_SCAN',
                :refillId,
                CURRENT_TIMESTAMP,
                :latitude,
                :longitude,
                :accuracy
            )
        ";

        $scanStmt = $db->prepare($scanSql);

        $scanStmt->execute([
            ':bottleId' => $bottleId,
            ':accId' => $accId,
            ':refillId' => $refillId,
            ':latitude' => $latitude,
            ':longitude' => $longitude,
            ':accuracy' => $accuracy
        ]);

        $scanEventId = (int) $db->lastInsertId();


        /*
         * Commit both records.
         */

        $db->commit();


        /*
         * -----------------------------------------------------
         * 11. RETURN SUCCESS
         * -----------------------------------------------------
         */

        echo json_encode([
            "success" => true,
            "message" => "Bottle refilled successfully.",
            "data" => [
                "RefillID" => $refillId,
                "ScanEventID" => $scanEventId,
                "BottleID" => $bottleId,
                "BottleNumber" => $bottle['BottleNumber'],
                "BottleTypeID" => $bottle['BottleTypeID'],
                "BottleType" => $bottle['BottleType'],
                "Price" => $bottle['Price'],
                "Latitude" => $latitude,
                "Longitude" => $longitude,
                "LocationAccuracy" => $accuracy
            ]
        ]);

    } catch (Throwable $e) {

        if ($db->inTransaction()) {
            $db->rollBack();
        }

        throw $e;
    }

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}
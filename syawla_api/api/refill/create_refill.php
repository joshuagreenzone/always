
<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $input = json_decode(file_get_contents("php://input"), true);

    $bottleNumber = trim($input['bottleNumber'] ?? '');

    if ($bottleNumber === '') {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" => "Bottle number is required."
        ]);

        exit;
    }

    $database = new Database();
    $db = $database->connect();

    /*
     * ---------------------------------------------------------
     * 1. FIND THE BOTTLE
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
     * 2. FIND THE MOST RECENT REFILL
     * ---------------------------------------------------------
     *
     * This is used to determine whether the bottle has already
     * been refilled after its most recent pickup.
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
     * 3. FIND THE MOST RECENT PICKUP
     * ---------------------------------------------------------
     *
     * A bottle must have been physically picked up before
     * it can be refilled.
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
     * 4. BOTTLE MUST HAVE BEEN PICKED UP
     * ---------------------------------------------------------
     *
     * A bottle that has never been picked up cannot be refilled.
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
     * 5. CHECK WHETHER IT WAS ALREADY REFILLED
     *    AFTER ITS MOST RECENT PICKUP
     * ---------------------------------------------------------
     *
     * Valid:
     *
     *     PICKUP → REFILL
     *
     * Invalid:
     *
     *     PICKUP → REFILL → REFILL
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
     * 6. SAFETY CHECK
     * ---------------------------------------------------------
     *
     * Make sure the bottle has not already been scanned into
     * another delivery after its latest pickup.
     *
     * A bottle in this state must not be refilled.
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

        ORDER BY d.DeliveryDateTime DESC, odt.ODTID DESC

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
     * 7. CREATE NEW REFILL RECORD
     * ---------------------------------------------------------
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
            NOW()
        )
    ";

    $insertStmt = $db->prepare($insertSql);

    $insertStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $refillId = $db->lastInsertId();


    /*
     * ---------------------------------------------------------
     * 8. RETURN SUCCESS
     * ---------------------------------------------------------
     */

    echo json_encode([
        "success" => true,
        "message" => "Bottle refilled successfully.",
        "data" => [
            "RefillID" => $refillId,
            "BottleID" => $bottleId,
            "BottleNumber" => $bottle['BottleNumber'],
            "BottleTypeID" => $bottle['BottleTypeID'],
            "BottleType" => $bottle['BottleType'],
            "Price" => $bottle['Price']
        ]
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}


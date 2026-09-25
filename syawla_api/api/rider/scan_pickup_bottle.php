<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    $input = json_decode(
        file_get_contents('php://input'),
        true
    );

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $orderId = isset($input['orderId'])
        ? (int) $input['orderId']
        : 0;

    $deliveryId = isset($input['deliveryId'])
        ? (int) $input['deliveryId']
        : 0;

    $bottleNumber = isset($input['bottleNumber'])
        ? trim($input['bottleNumber'])
        : '';

    /*
     * GPS LOCATION
     *
     * Flutter will send these values when the bottle is scanned.
     *
     * They are optional for now so the PHP endpoint can still
     * be tested before the Flutter GPS update is made.
     */

    $latitude = isset($input['latitude'])
        ? (float) $input['latitude']
        : null;

    $longitude = isset($input['longitude'])
        ? (float) $input['longitude']
        : null;

    $locationAccuracy = isset($input['accuracy'])
        ? (float) $input['accuracy']
        : null;

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0 ||
        $bottleNumber === ''
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid pickup information.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 1. VERIFY DELIVERED DELIVERY BELONGS TO THIS RIDER
     * ---------------------------------------------------------
     */

    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,

            o.Quantity,
            o.CustomerID,
            c.CustomerName,
            o.BottleTypeID,

            bt.BottleType

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        INNER JOIN bottle_types bt
            ON o.BottleTypeID = bt.BottleTypeID

        INNER JOIN accounts a
            ON d.AccID = a.AccID

        WHERE d.DeliveryID = :deliveryId
          AND d.OrderID = :orderId
          AND d.AccID = :accId
          AND a.AccType = 'RIDER'

        LIMIT 1
    ";

    $deliveryStmt = $db->prepare($deliverySql);

    $deliveryStmt->execute([
        ':deliveryId' => $deliveryId,
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $delivery = $deliveryStmt->fetch();

    if (!$delivery) {

        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' =>
                'Delivery not found or not assigned to this rider.'
        ]);

        exit;
    }

    /*
     * Pickup is only allowed after the delivery has been
     * completed.
     */

    if ($delivery['DeliveryStatus'] !== 'DELIVERED') {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle cannot be picked up because the delivery has not been completed.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 2. FIND PHYSICAL BOTTLE
     * ---------------------------------------------------------
     */

    $bottleSql = "
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            bt.BottleType

        FROM bottles b

        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID

        WHERE b.BottleNumber = :bottleNumber

        LIMIT 1
    ";

    $bottleStmt = $db->prepare($bottleSql);

    $bottleStmt->execute([
        ':bottleNumber' => $bottleNumber
    ]);

    $bottle = $bottleStmt->fetch();

    if (!$bottle) {

        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' => 'Bottle not found.'
        ]);

        exit;
    }

    $bottleId = (int) $bottle['BottleID'];

    /*
     * ---------------------------------------------------------
     * 3. VERIFY BOTTLE TYPE
     * ---------------------------------------------------------
     */

    if (
        (int) $bottle['BottleTypeID'] !==
        (int) $delivery['BottleTypeID']
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle type does not match the delivered order.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 4. VERIFY THIS EXACT BOTTLE WAS DELIVERED
     *    FOR THIS ORDER AND DELIVERY
     * ---------------------------------------------------------
     */

    $deliveredSql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID,
            odt.BottleID

        FROM order_delivery_transaction odt

        INNER JOIN delivery d
            ON odt.DeliveryID = d.DeliveryID

        WHERE odt.BottleID = :bottleId
          AND odt.OrderID = :orderId
          AND odt.DeliveryID = :deliveryId
          AND d.DeliveryStatus = 'DELIVERED'

        LIMIT 1
    ";

    $deliveredStmt = $db->prepare($deliveredSql);

    $deliveredStmt->execute([
        ':bottleId' => $bottleId,
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $delivered = $deliveredStmt->fetch();

    if (!$delivered) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle was not recorded as delivered for this customer.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 5. CHECK IF THIS BOTTLE WAS ALREADY PICKED UP
     *    FOR THIS DELIVERY
     * ---------------------------------------------------------
     */

    $alreadyPickedSql = "
        SELECT
            dpt.DPTID

        FROM delivery_pickup_transaction dpt

        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID

        WHERE dpt.BottleID = :bottleId
          AND p.DeliveryID = :deliveryId
          AND p.AccID = :accId

        LIMIT 1
    ";

    $alreadyPickedStmt = $db->prepare(
        $alreadyPickedSql
    );

    $alreadyPickedStmt->execute([
        ':bottleId' => $bottleId,
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    if ($alreadyPickedStmt->fetch()) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle has already been picked up for this delivery.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 6. COUNT ALL BOTTLES ALREADY PICKED UP
     * ---------------------------------------------------------
     */

    $currentCountSql = "
        SELECT
            COUNT(DISTINCT dpt.BottleID) AS PickedUpCount

        FROM pickup p

        INNER JOIN delivery_pickup_transaction dpt
            ON p.PickUpID = dpt.PickUpID

        WHERE p.DeliveryID = :deliveryId
          AND p.AccID = :accId
    ";

    $currentCountStmt = $db->prepare(
        $currentCountSql
    );

    $currentCountStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $currentCount = $currentCountStmt->fetch();

    $pickedUpCount = (int) $currentCount['PickedUpCount'];

    $requiredCount = (int) $delivery['Quantity'];

    $remainingBeforePickup =
        $requiredCount - $pickedUpCount;

    if ($remainingBeforePickup <= 0) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'All required bottles have already been picked up.',

            'data' => [
                'pickedUpQuantity' => $pickedUpCount,
                'requiredQuantity' => $requiredCount,
                'remainingQuantity' => 0
            ]
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 7. CREATE OR GET PICKUP SESSION
     * ---------------------------------------------------------
     *
     * We continue to reuse the existing pickup session.
     *
     * The individual scan time/location is now stored separately
     * in bottle_scan_event.
     */

    $pickupSql = "
        SELECT
            PickUpID

        FROM pickup

        WHERE DeliveryID = :deliveryId
          AND AccID = :accId

        ORDER BY PickUpID ASC

        LIMIT 1
    ";

    $pickupStmt = $db->prepare($pickupSql);

    $pickupStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $pickup = $pickupStmt->fetch();

    /*
     * ---------------------------------------------------------
     * 8. START DATABASE TRANSACTION
     * ---------------------------------------------------------
     */

    $db->beginTransaction();

    try {

        /*
         * Create pickup session if one does not already exist.
         */

        if ($pickup) {

            $pickUpId = (int) $pickup['PickUpID'];

        } else {

            $insertPickupSql = "
                INSERT INTO pickup
                (
                    DeliveryID,
                    AccID,
                    PickUpDateTime
                )
                VALUES
                (
                    :deliveryId,
                    :accId,
                    CURRENT_TIMESTAMP
                )
            ";

            $insertPickupStmt = $db->prepare(
                $insertPickupSql
            );

            $insertPickupStmt->execute([
                ':deliveryId' => $deliveryId,
                ':accId' => $accId
            ]);

            $pickUpId = (int) $db->lastInsertId();
        }

        /*
         * -----------------------------------------------------
         * 9. INSERT PICKUP TRANSACTION
         * -----------------------------------------------------
         */

        $insertTransactionSql = "
            INSERT INTO delivery_pickup_transaction
            (
                PickUpID,
                BottleID
            )
            VALUES
            (
                :pickUpId,
                :bottleId
            )
        ";

        $insertTransactionStmt = $db->prepare(
            $insertTransactionSql
        );

        $insertTransactionStmt->execute([
            ':pickUpId' => $pickUpId,
            ':bottleId' => $bottleId
        ]);

        $dptId = (int) $db->lastInsertId();

        /*
         * -----------------------------------------------------
         * 10. RECORD PHYSICAL PICKUP SCAN
         * -----------------------------------------------------
         *
         * This is the permanent audit record.
         *
         * ScanDateTime comes from MariaDB server time.
         */

        $scanEventSql = "
            INSERT INTO bottle_scan_event
            (
                BottleID,
                AccID,
                EventType,
                OrderID,
                DeliveryID,
                PickUpID,
                DPTID,
                ScanDateTime,
                Latitude,
                Longitude,
                LocationAccuracy
            )
            VALUES
            (
                :bottleId,
                :accId,
                'PICKUP_SCAN',
                :orderId,
                :deliveryId,
                :pickUpId,
                :dptId,
                CURRENT_TIMESTAMP,
                :latitude,
                :longitude,
                :locationAccuracy
            )
        ";

        $scanEventStmt = $db->prepare(
            $scanEventSql
        );

        $scanEventStmt->execute([
            ':bottleId' => $bottleId,
            ':accId' => $accId,
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId,
            ':pickUpId' => $pickUpId,
            ':dptId' => $dptId,
            ':latitude' => $latitude,
            ':longitude' => $longitude,
            ':locationAccuracy' => $locationAccuracy
        ]);

        $scanEventId = (int) $db->lastInsertId();

        /*
         * -----------------------------------------------------
         * 11. UPDATE PICKUP ACTIVITY TIMESTAMP
         * -----------------------------------------------------
         *
         * This is still useful as the overall pickup session
         * timestamp.
         *
         * The exact time of each bottle scan is preserved in
         * bottle_scan_event.
         */

        $updatePickupSql = "
            UPDATE pickup

            SET PickUpDateTime = CURRENT_TIMESTAMP

            WHERE PickUpID = :pickUpId
              AND DeliveryID = :deliveryId
              AND AccID = :accId
        ";

        $updatePickupStmt = $db->prepare(
            $updatePickupSql
        );

        $updatePickupStmt->execute([
            ':pickUpId' => $pickUpId,
            ':deliveryId' => $deliveryId,
            ':accId' => $accId
        ]);

        /*
         * Everything succeeded.
         */

        $db->commit();

    } catch (PDOException $e) {

        if ($db->inTransaction()) {
            $db->rollBack();
        }

        throw $e;
    }

    /*
     * ---------------------------------------------------------
     * 12. COUNT TOTAL PICKED UP BOTTLES
     * ---------------------------------------------------------
     */

    $countSql = "
        SELECT
            COUNT(DISTINCT dpt.BottleID) AS PickedUpCount

        FROM pickup p

        INNER JOIN delivery_pickup_transaction dpt
            ON p.PickUpID = dpt.PickUpID

        WHERE p.DeliveryID = :deliveryId
          AND p.AccID = :accId
    ";

    $countStmt = $db->prepare($countSql);

    $countStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $count = $countStmt->fetch();

    $pickedUpCount = (int) $count['PickedUpCount'];

    $remainingQuantity =
        $requiredCount - $pickedUpCount;

    /*
     * ---------------------------------------------------------
     * 13. SUCCESS RESPONSE
     * ---------------------------------------------------------
     */

    echo json_encode([
        'success' => true,

        'message' =>
            $remainingQuantity > 0
                ? 'Bottle pickup recorded successfully. Some bottles remain to be picked up.'
                : 'Bottle pickup recorded successfully. All bottles have now been picked up.',

        'data' => [
            'pickUpId' => $pickUpId,
            'dptId' => $dptId,
            'scanEventId' => $scanEventId,

            'bottleId' => $bottleId,
            'bottleNumber' => $bottle['BottleNumber'],
            'bottleType' => $bottle['BottleType'],

            'pickedUpQuantity' => $pickedUpCount,
            'requiredQuantity' => $requiredCount,
            'remainingQuantity' => $remainingQuantity
        ]
    ]);

} catch (PDOException $e) {

    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.'
    ]);
}
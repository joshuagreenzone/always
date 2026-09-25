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

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0 ||
        $bottleNumber === ''
    ) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid delivery or bottle information.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 1. Verify rider owns the delivery
     * ---------------------------------------------------------
     */

    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,

            o.BottleTypeID,
            o.Quantity,
            o.OrderStatus,

            bt.BottleType

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

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

        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' =>
                'This delivery is not assigned to this rider.'
        ]);

        exit;
    }

    if ($delivery['DeliveryStatus'] === 'COMPLETED') {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'This delivery has already been completed.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 2. Find the physical bottle
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
            'message' =>
                'Bottle not found.'
        ]);

        exit;
    }

    $bottleId = (int) $bottle['BottleID'];

    /*
     * ---------------------------------------------------------
     * 3. CHECK GALLON TYPE
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
                'Wrong gallon type. This order requires ' .
                $delivery['BottleType'] .
                ', but the scanned bottle is ' .
                $bottle['BottleType'] .
                '.',
            'data' => [
                'requiredBottleType' =>
                    $delivery['BottleType'],
                'scannedBottleType' =>
                    $bottle['BottleType']
            ]
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 4. CHECK IF ALREADY SCANNED FOR THIS DELIVERY
     * ---------------------------------------------------------
     */

    $duplicateSql = "
        SELECT ODTID
        FROM order_delivery_transaction
        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
          AND BottleID = :bottleId
        LIMIT 1
    ";

    $duplicateStmt = $db->prepare($duplicateSql);

    $duplicateStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId,
        ':bottleId' => $bottleId
    ]);

    if ($duplicateStmt->fetch()) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle has already been scanned.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 5. CHECK IF BOTTLE IS CURRENTLY WITH ANOTHER CUSTOMER
     *
     * A bottle becomes unavailable when it was delivered and
     * has NOT yet been picked up.
     *
     * We look for a delivery transaction where:
     *
     *   delivery completed
     *
     * AND
     *
     *   there is no later pickup transaction for that bottle.
     * ---------------------------------------------------------
     */

    $activeBottleSql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID,
            d.DeliveryDateTime,
            d.DeliveryStatus

        FROM order_delivery_transaction odt

        INNER JOIN delivery d
            ON odt.DeliveryID = d.DeliveryID

        WHERE odt.BottleID = :bottleId

          AND d.DeliveryStatus = 'COMPLETED'

          AND NOT EXISTS (

              SELECT 1

              FROM delivery_pickup_transaction dpt

              INNER JOIN pickup p
                  ON dpt.PickUpID = p.PickUpID

              WHERE dpt.BottleID = odt.BottleID
                AND p.DeliveryID = odt.DeliveryID
                AND p.PickUpDateTime > d.DeliveryDateTime
          )

        ORDER BY d.DeliveryDateTime DESC

        LIMIT 1
    ";

    $activeBottleStmt = $db->prepare($activeBottleSql);

    $activeBottleStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $activeBottle = $activeBottleStmt->fetch();

    if ($activeBottle) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle has already been dropped off and has not been picked up yet.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 6. CHECK IF BOTTLE IS ALREADY SCANNED FOR ANOTHER
     *    ACTIVE DELIVERY
     * ---------------------------------------------------------
     *
     * This prevents the same bottle from being assigned to
     * two deliveries before either delivery is completed.
     */

    $activeDeliverySql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID,
            d.DeliveryStatus

        FROM order_delivery_transaction odt

        INNER JOIN delivery d
            ON odt.DeliveryID = d.DeliveryID

        WHERE odt.BottleID = :bottleId

          AND d.DeliveryStatus = 'ASSIGNED'

          AND NOT (
              odt.OrderID = :orderId
              AND odt.DeliveryID = :deliveryId
          )

        LIMIT 1
    ";

    $activeDeliveryStmt = $db->prepare(
        $activeDeliverySql
    );

    $activeDeliveryStmt->execute([
        ':bottleId' => $bottleId,
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    if ($activeDeliveryStmt->fetch()) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle is already assigned to another active delivery.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 7. CHECK BOTTLE REFILL STATUS
     *
     * A bottle must have a refill after its most recent pickup
     * before it can be delivered again.
     * ---------------------------------------------------------
     */

    $refillSql = "
        SELECT
            r.RefillID,
            r.RefillDateTime

        FROM refill r

        WHERE r.BottleID = :bottleId

        ORDER BY r.RefillDateTime DESC

        LIMIT 1
    ";

    $refillStmt = $db->prepare($refillSql);

    $refillStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestRefill = $refillStmt->fetch();

    if (!$latestRefill) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle has not been refilled yet.'
        ]);

        exit;
    }

    /*
     * Find the latest completed delivery/pickup cycle.
     */

    $latestPickupSql = "
        SELECT
            p.PickUpID,
            p.PickUpDateTime

        FROM delivery_pickup_transaction dpt

        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID

        WHERE dpt.BottleID = :bottleId

        ORDER BY p.PickUpDateTime DESC

        LIMIT 1
    ";

    $latestPickupStmt = $db->prepare(
        $latestPickupSql
    );

    $latestPickupStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestPickup = $latestPickupStmt->fetch();

    /*
     * If there was a pickup after the latest refill,
     * the bottle needs another refill before delivery.
     */

    if (
        $latestPickup &&
        strtotime($latestRefill['RefillDateTime']) <=
        strtotime($latestPickup['PickUpDateTime'])
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This bottle has been picked up but has not been refilled yet.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 8. CHECK ORDER QUANTITY
     * ---------------------------------------------------------
     */

    $countSql = "
        SELECT COUNT(*) AS ScannedCount
        FROM order_delivery_transaction
        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
    ";

    $countStmt = $db->prepare($countSql);

    $countStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $countResult = $countStmt->fetch();

    $scannedCount = (int) $countResult['ScannedCount'];
    $requiredCount = (int) $delivery['Quantity'];

    if ($scannedCount >= $requiredCount) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'All required bottles have already been scanned.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 9. INSERT SCANNED BOTTLE
     * ---------------------------------------------------------
     */

    $insertSql = "
        INSERT INTO order_delivery_transaction
        (
            OrderID,
            DeliveryID,
            BottleID
        )
        VALUES
        (
            :orderId,
            :deliveryId,
            :bottleId
        )
    ";

    $insertStmt = $db->prepare($insertSql);

    $insertStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId,
        ':bottleId' => $bottleId
    ]);

    /*
     * ---------------------------------------------------------
     * 10. RETURN SUCCESS
     * ---------------------------------------------------------
     */

    $newScannedCount = $scannedCount + 1;

    echo json_encode([
        'success' => true,
        'message' => 'Bottle scanned successfully.',
        'data' => [
            'bottleId' => $bottleId,
            'bottleNumber' => $bottle['BottleNumber'],
            'bottleTypeId' => (int) $bottle['BottleTypeID'],
            'bottleType' => $bottle['BottleType'],
            'requiredQuantity' => $requiredCount,
            'scannedQuantity' => $newScannedCount
        ]
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.'
    ]);
}
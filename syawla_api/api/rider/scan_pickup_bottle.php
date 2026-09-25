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
            'message' => 'Invalid pickup information.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 1. Verify delivered delivery belongs to this rider
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
     * 2. Find physical bottle
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
     * 3. Verify bottle type
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
     * 4. Verify this exact bottle was delivered
     *    for this order and delivery.
     * ---------------------------------------------------------
     */

    $deliveredSql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID

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
     * 5. Check if this exact bottle was already picked up
     *    for this delivery.
     *
     *    This is NOT a global bottle check because bottles
     *    are reusable.
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
     * 6. Count ALL bottles already picked up for this delivery.
     *
     *    This is the important part for partial pickup.
     *
     *    Example:
     *
     *    Delivered = 5
     *    Already picked up = 3
     *    Remaining = 2
     *
     *    The rider may continue scanning until the total
     *    reaches 5.
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
     * 7. Create or get pickup session
     *
     *    The existing pickup session is reused so multiple
     *    partial scans can accumulate against the same delivery.
     * ---------------------------------------------------------
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
                NOW()
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
     * ---------------------------------------------------------
     * 8. Insert pickup transaction
     * ---------------------------------------------------------
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

    /*
     * ---------------------------------------------------------
     * 9. Count total picked up bottles AFTER this scan.
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
     * 10. Update pickup timestamp.
     *
     *     This records the latest pickup activity.
     * ---------------------------------------------------------
     */

    $updatePickupSql = "
        UPDATE pickup

        SET PickUpDateTime = NOW()

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

    echo json_encode([
        'success' => true,
        'message' =>
            $remainingQuantity > 0
                ? 'Bottle pickup recorded successfully. Some bottles remain to be picked up.'
                : 'Bottle pickup recorded successfully. All bottles have now been picked up.',
        'data' => [
            'pickUpId' => $pickUpId,
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
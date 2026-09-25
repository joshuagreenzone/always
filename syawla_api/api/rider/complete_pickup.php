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

    $pickUpId = isset($input['pickUpId'])
        ? (int) $input['pickUpId']
        : 0;

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0 ||
        $pickUpId <= 0
    ) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid pickup information.'
        ]);

        exit;
    }

    /*
     * Verify pickup belongs to rider and delivery.
     */

    $pickupSql = "
        SELECT
            p.PickUpID,
            p.DeliveryID,
            p.AccID,
            d.OrderID,
            d.DeliveryStatus,
            o.Quantity

        FROM pickup p

        INNER JOIN delivery d
            ON p.DeliveryID = d.DeliveryID

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        WHERE p.PickUpID = :pickUpId
          AND p.DeliveryID = :deliveryId
          AND p.AccID = :accId
          AND d.OrderID = :orderId
          AND d.DeliveryStatus = 'DELIVERED'

        LIMIT 1
    ";

    $pickupStmt = $db->prepare($pickupSql);

    $pickupStmt->execute([
        ':pickUpId' => $pickUpId,
        ':deliveryId' => $deliveryId,
        ':accId' => $accId,
        ':orderId' => $orderId
    ]);

    $pickup = $pickupStmt->fetch();

    if (!$pickup) {

        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' =>
                'Pickup session not found.'
        ]);

        exit;
    }

    /*
     * Count bottles actually delivered.
     */

    $deliveredSql = "
        SELECT COUNT(DISTINCT BottleID) AS DeliveredCount

        FROM order_delivery_transaction

        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
    ";

    $deliveredStmt = $db->prepare(
        $deliveredSql
    );

    $deliveredStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $delivered = $deliveredStmt->fetch();

    /*
     * Count bottles picked up.
     */

    $pickedUpSql = "
        SELECT COUNT(DISTINCT BottleID) AS PickedUpCount

        FROM delivery_pickup_transaction

        WHERE PickUpID = :pickUpId
    ";

    $pickedUpStmt = $db->prepare(
        $pickedUpSql
    );

    $pickedUpStmt->execute([
        ':pickUpId' => $pickUpId
    ]);

    $pickedUp = $pickedUpStmt->fetch();

    $deliveredCount =
        (int) $delivered['DeliveredCount'];

    $pickedUpCount =
        (int) $pickedUp['PickedUpCount'];

    if ($pickedUpCount < $deliveredCount) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Not all delivered bottles have been picked up.',
            'data' => [
                'delivered' => $deliveredCount,
                'pickedUp' => $pickedUpCount
            ]
        ]);

        exit;
    }

    if ($pickedUpCount > $deliveredCount) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Picked up bottle count exceeds delivered bottle count.'
        ]);

        exit;
    }

    /*
     * Update pickup completion time.
     */

    $db->beginTransaction();

    $updateSql = "
        UPDATE pickup
        SET PickUpDateTime = NOW()
        WHERE PickUpID = :pickUpId
          AND DeliveryID = :deliveryId
          AND AccID = :accId
    ";

    $updateStmt = $db->prepare($updateSql);

    $updateStmt->execute([
        ':pickUpId' => $pickUpId,
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $db->commit();

    echo json_encode([
        'success' => true,
        'message' =>
            'Bottle pickup completed successfully.',
        'data' => [
            'pickUpId' => $pickUpId,
            'deliveryId' => $deliveryId,
            'orderId' => $orderId,
            'pickedUpCount' => $pickedUpCount
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
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

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0
    ) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid delivery information.'
        ]);

        exit;
    }

    /*
     * Verify rider + delivery + order.
     */
    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,
            o.Quantity,
            o.OrderStatus
        FROM delivery d
        INNER JOIN orders o
            ON d.OrderID = o.OrderID
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
                'This delivery is not assigned to you.'
        ]);

        exit;
    }

    /*
     * Delivery is already finished.
     */
    if ($delivery['DeliveryStatus'] === 'DELIVERED') {
        echo json_encode([
            'success' => true,
            'message' =>
                'Delivery has already been completed.',
            'data' => [
                'orderId' => $orderId,
                'deliveryId' => $deliveryId,
                'deliveryStatus' => 'DELIVERED',
                'orderStatus' => 'DELIVERED'
            ]
        ]);

        exit;
    }

    /*
     * Make sure all required physical bottles
     * were scanned.
     */
    $bottleCountSql = "
        SELECT COUNT(*) AS ScannedCount
        FROM order_delivery_transaction
        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
    ";

    $bottleCountStmt = $db->prepare($bottleCountSql);

    $bottleCountStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $bottleCount = $bottleCountStmt->fetch();

    $required = (int) $delivery['Quantity'];
    $scanned = (int) $bottleCount['ScannedCount'];

    if ($scanned < $required) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Not all required bottles have been scanned.',
            'data' => [
                'required' => $required,
                'scanned' => $scanned
            ]
        ]);

        exit;
    }

    if ($scanned > $required) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'The scanned bottle count exceeds the order quantity.'
        ]);

        exit;
    }

    $db->beginTransaction();

    /*
     * Mark delivery as DELIVERED.
     *
     * This matches the actual DeliveryStatus enum:
     *
     * ASSIGNED
     * OUT_FOR_DELIVERY
     * DELIVERED
     * CANCELLED
     */
    $updateDeliverySql = "
        UPDATE delivery
        SET
            DeliveryStatus = 'DELIVERED',
            DeliveryDateTime = NOW()
        WHERE DeliveryID = :deliveryId
          AND OrderID = :orderId
          AND AccID = :accId
    ";

    $updateDeliveryStmt = $db->prepare(
        $updateDeliverySql
    );

    $updateDeliveryStmt->execute([
        ':deliveryId' => $deliveryId,
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    /*
     * Mark order as delivered.
     *
     * PaymentStatus remains independent.
     *
     * Therefore an unpaid or partially paid order
     * can still be delivered and retain an
     * outstanding balance.
     */
    $updateOrderSql = "
        UPDATE orders
        SET OrderStatus = 'DELIVERED'
        WHERE OrderID = :orderId
    ";

    $updateOrderStmt = $db->prepare(
        $updateOrderSql
    );

    $updateOrderStmt->execute([
        ':orderId' => $orderId
    ]);

    $db->commit();

    echo json_encode([
        'success' => true,
        'message' =>
            'Delivery completed successfully.',
        'data' => [
            'orderId' => $orderId,
            'deliveryId' => $deliveryId,
            'deliveryStatus' => 'DELIVERED',
            'orderStatus' => 'DELIVERED'
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
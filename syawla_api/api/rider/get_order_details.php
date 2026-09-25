<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

try {

    $database = new Database();
    $db = $database->connect();

    $orderId = isset($_GET['orderId'])
        ? (int) $_GET['orderId']
        : 0;

    $accId = isset($_GET['accId'])
        ? (int) $_GET['accId']
        : 0;

    if ($orderId <= 0 || $accId <= 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid order or rider account.'
        ]);

        exit;
    }

    $sql = "
        SELECT
            o.OrderID,
            o.CustomerID,
            c.CustomerName,

            o.BottleTypeID,
            bt.BottleType,

            o.Quantity,
            o.UnitPrice,

            (o.Quantity * o.UnitPrice) AS TotalAmount,

            o.OrderDateTime,
            o.OrderStatus,
            o.PaymentStatus,

            d.DeliveryID,
            d.DeliveryDateTime,
            d.DeliveryStatus

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        INNER JOIN bottle_types bt
            ON o.BottleTypeID = bt.BottleTypeID

        WHERE o.OrderID = :orderId
          AND d.AccID = :accId

        LIMIT 1
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $order = $stmt->fetch();

    if (!$order) {
        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' => 'Order not found or not assigned to this rider.'
        ]);

        exit;
    }

    echo json_encode([
        'success' => true,
        'data' => $order
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.'
    ]);
}
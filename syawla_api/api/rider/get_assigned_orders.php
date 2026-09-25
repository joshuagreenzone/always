<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

try {

    // Create database connection
    $database = new Database();
    $db = $database->connect();

    // Get rider account ID
    $accId = isset($_GET['accId'])
        ? (int) $_GET['accId']
        : 0;

    if ($accId <= 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid rider account.'
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

        WHERE d.AccID = :accId
          AND d.DeliveryStatus = 'ASSIGNED'

        ORDER BY d.DeliveryDateTime ASC
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':accId' => $accId
    ]);

    $orders = $stmt->fetchAll();

    echo json_encode([
        'success' => true,
        'data' => $orders
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
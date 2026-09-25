<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

try {

    $database = new Database();
    $db = $database->connect();

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
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryDateTime,
            d.DeliveryStatus,

            o.CustomerID,
            c.CustomerName,

            o.BottleTypeID,
            bt.BottleType,

            o.Quantity,

            COUNT(DISTINCT odt.BottleID) AS DeliveredBottleCount,

            COUNT(
                DISTINCT CASE
                    WHEN dpt.BottleID IS NOT NULL
                    THEN odt.BottleID
                END
            ) AS PickedUpBottleCount

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        INNER JOIN bottle_types bt
            ON o.BottleTypeID = bt.BottleTypeID

        INNER JOIN order_delivery_transaction odt
            ON d.DeliveryID = odt.DeliveryID
           AND d.OrderID = odt.OrderID

        LEFT JOIN pickup p
            ON p.DeliveryID = d.DeliveryID
           AND p.AccID = d.AccID

        LEFT JOIN delivery_pickup_transaction dpt
            ON dpt.PickUpID = p.PickUpID
           AND dpt.BottleID = odt.BottleID

        INNER JOIN accounts a
            ON d.AccID = a.AccID

        WHERE d.AccID = :accId
          AND a.AccType = 'RIDER'
          AND d.DeliveryStatus = 'DELIVERED'

        GROUP BY
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryDateTime,
            d.DeliveryStatus,

            o.CustomerID,
            c.CustomerName,

            o.BottleTypeID,
            bt.BottleType,

            o.Quantity

        HAVING
            COUNT(DISTINCT odt.BottleID) >
            COUNT(
                DISTINCT CASE
                    WHEN dpt.BottleID IS NOT NULL
                    THEN odt.BottleID
                END
            )

        ORDER BY
            d.DeliveryDateTime ASC
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
        'message' => 'Database error: ' . $e->getMessage()
    ]);
}
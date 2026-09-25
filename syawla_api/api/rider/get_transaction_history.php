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
            o.OrderID,
            'DELIVERED' AS TransactionType,

            c.CustomerName,
            c.CustomerAddress,

            bt.BottleType,

            o.Quantity,
            o.UnitPrice,

            (o.Quantity * o.UnitPrice) AS TotalAmount,

            COALESCE(
                (
                    SELECT SUM(opt.Amount)
                    FROM order_payment_transaction opt
                    WHERE opt.OrderID = o.OrderID
                ),
                0
            ) AS PaidAmount,

            (
                (o.Quantity * o.UnitPrice)
                -
                COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                )
            ) AS Balance,

            CASE
                WHEN COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                ) <= 0
                    THEN 'UNPAID'

                WHEN COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                ) >= (o.Quantity * o.UnitPrice)
                    THEN 'PAID'

                ELSE 'PARTIALLY_PAID'
            END AS PaymentStatus,

            d.DeliveryDateTime AS TransactionDateTime

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        INNER JOIN bottle_types bt
            ON o.BottleTypeID = bt.BottleTypeID

        WHERE d.AccID = :deliveryAccId
        AND d.DeliveryStatus = 'DELIVERED'


        UNION ALL


        SELECT
            o.OrderID,
            'PICKED_UP' AS TransactionType,

            c.CustomerName,
            c.CustomerAddress,

            bt.BottleType,

            o.Quantity,
            o.UnitPrice,

            (o.Quantity * o.UnitPrice) AS TotalAmount,

            COALESCE(
                (
                    SELECT SUM(opt.Amount)
                    FROM order_payment_transaction opt
                    WHERE opt.OrderID = o.OrderID
                ),
                0
            ) AS PaidAmount,

            (
                (o.Quantity * o.UnitPrice)
                -
                COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                )
            ) AS Balance,

            CASE
                WHEN COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                ) <= 0
                    THEN 'UNPAID'

                WHEN COALESCE(
                    (
                        SELECT SUM(opt.Amount)
                        FROM order_payment_transaction opt
                        WHERE opt.OrderID = o.OrderID
                    ),
                    0
                ) >= (o.Quantity * o.UnitPrice)
                    THEN 'PAID'

                ELSE 'PARTIALLY_PAID'
            END AS PaymentStatus,

            p.PickUpDateTime AS TransactionDateTime

        FROM pickup p

        INNER JOIN delivery d
            ON p.DeliveryID = d.DeliveryID

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        INNER JOIN bottle_types bt
            ON o.BottleTypeID = bt.BottleTypeID

        WHERE p.AccID = :pickupAccId

        ORDER BY TransactionDateTime DESC
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':deliveryAccId' => $accId,
        ':pickupAccId' => $accId
    ]);

    $transactions = $stmt->fetchAll();

    echo json_encode([
        'success' => true,
        'data' => $transactions
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.',
        'error' => $e->getMessage()
    ]);
}
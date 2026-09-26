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

    /*
     * =========================================================
     * GET ASSIGNED ORDERS
     * =========================================================
     */

    $sql = "
        SELECT
            o.OrderID,
            o.CustomerID,
            c.CustomerName,

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

        WHERE d.AccID = :accId
          AND d.DeliveryStatus = 'ASSIGNED'

        ORDER BY d.DeliveryDateTime ASC
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':accId' => $accId
    ]);

    $orders = $stmt->fetchAll(PDO::FETCH_ASSOC);

    /*
     * =========================================================
     * GET ITEMS FOR EACH ORDER
     * =========================================================
     */

    $itemSql = "
        SELECT
            oi.OrderItemID,
            oi.OrderID,
            oi.BottleTypeID,
            bt.BottleType,
            oi.Quantity,
            oi.UnitPrice,

            (oi.Quantity * oi.UnitPrice) AS ItemTotal

        FROM order_items oi

        INNER JOIN bottle_types bt
            ON oi.BottleTypeID = bt.BottleTypeID

        WHERE oi.OrderID = :orderId

        ORDER BY oi.OrderItemID ASC
    ";

    $itemStmt = $db->prepare($itemSql);

    foreach ($orders as &$order) {

        $orderId =
            (int) $order['OrderID'];

        $itemStmt->execute([
            ':orderId' => $orderId
        ]);

        $items =
            $itemStmt->fetchAll(PDO::FETCH_ASSOC);

        $totalQuantity = 0;
        $totalAmount = 0;

        foreach ($items as &$item) {

            $item['OrderItemID'] =
                (int) $item['OrderItemID'];

            $item['OrderID'] =
                (int) $item['OrderID'];

            $item['BottleTypeID'] =
                (int) $item['BottleTypeID'];

            $item['Quantity'] =
                (int) $item['Quantity'];

            $item['UnitPrice'] =
                (float) $item['UnitPrice'];

            $item['ItemTotal'] =
                (float) $item['ItemTotal'];

            $totalQuantity +=
                $item['Quantity'];

            $totalAmount +=
                $item['ItemTotal'];
        }

        unset($item);

        $order['OrderID'] =
            $orderId;

        $order['CustomerID'] =
            (int) $order['CustomerID'];

        $order['DeliveryID'] =
            (int) $order['DeliveryID'];

        $order['TotalQuantity'] =
            $totalQuantity;

        $order['TotalAmount'] =
            $totalAmount;

        $order['items'] =
            $items;
    }

    unset($order);

    /*
     * =========================================================
     * RESPONSE
     * =========================================================
     */

    echo json_encode([
        'success' => true,
        'data' => $orders
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.'
    ]);
}
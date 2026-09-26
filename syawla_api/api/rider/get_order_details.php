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

    /*
     * =========================================================
     * GET ORDER + DELIVERY
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
            o.Notes,

            d.DeliveryID,
            d.DeliveryDateTime,
            d.DeliveryStatus

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN customers c
            ON o.CustomerID = c.CustomerID

        WHERE o.OrderID = :orderId
          AND d.AccID = :accId

        LIMIT 1
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $order = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$order) {
        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' => 'Order not found or not assigned to this rider.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * GET ORDER ITEMS
     * =========================================================
     */

    $itemSql = "
        SELECT
            oi.OrderItemID,
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

    $itemStmt->execute([
        ':orderId' => $orderId
    ]);

    $items = $itemStmt->fetchAll(PDO::FETCH_ASSOC);

    /*
     * =========================================================
     * CALCULATE TOTALS
     * =========================================================
     */

    $totalQuantity = 0;
    $totalAmount = 0;

    foreach ($items as &$item) {

        $item['OrderItemID'] =
            (int) $item['OrderItemID'];

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

    /*
     * =========================================================
     * FORMAT ORDER
     * =========================================================
     */

    $order['OrderID'] =
        (int) $order['OrderID'];

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

    /*
     * =========================================================
     * RESPONSE
     * =========================================================
     */

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
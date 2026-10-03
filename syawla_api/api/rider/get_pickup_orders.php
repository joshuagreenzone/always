<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

try {
    $database = new Database();
    $db = $database->connect();

    $accId = isset($_GET['accId']) ? (int) $_GET['accId'] : 0;

    if ($accId <= 0) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => 'Invalid rider account.'
        ]);
        exit;
    }

    /*
     * Get bottles actually delivered for each delivery
     * and bottle type. Undelivered bottles are excluded
     * because they have no order_delivery_transaction row.
     */
    $sql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryDateTime,
            d.DeliveryStatus,
            o.CustomerID,
            c.CustomerName,
            oi.OrderItemID,
            oi.BottleTypeID,
            bt.BottleType,

            COUNT(DISTINCT odt.BottleID) AS DeliveredBottleCount,

            COUNT(
                DISTINCT CASE
                    WHEN dpt.BottleID IS NOT NULL
                    THEN odt.BottleID
                END
            ) AS PickedUpBottleCount,

            (
                COUNT(DISTINCT odt.BottleID)
                -
                COUNT(
                    DISTINCT CASE
                        WHEN dpt.BottleID IS NOT NULL
                        THEN odt.BottleID
                    END
                )
            ) AS RemainingBottleCount

        FROM delivery d

        INNER JOIN orders o
            ON o.OrderID = d.OrderID

        INNER JOIN customers c
            ON c.CustomerID = o.CustomerID

        INNER JOIN order_delivery_transaction odt
            ON odt.DeliveryID = d.DeliveryID
           AND odt.OrderID = d.OrderID

        INNER JOIN bottles b
            ON b.BottleID = odt.BottleID

        INNER JOIN bottle_types bt
            ON bt.BottleTypeID = b.BottleTypeID

        INNER JOIN accounts a
            ON a.AccID = d.AccID

        LEFT JOIN order_items oi
            ON oi.OrderItemID = odt.OrderItemID
           AND oi.OrderID = odt.OrderID
           AND oi.BottleTypeID = b.BottleTypeID

        LEFT JOIN pickup p
            ON p.DeliveryID = d.DeliveryID
           AND p.AccID = d.AccID

        LEFT JOIN delivery_pickup_transaction dpt
            ON dpt.PickUpID = p.PickUpID
           AND dpt.BottleID = odt.BottleID

        WHERE d.AccID = :accId
          AND a.AccType = 'RIDER'
          AND d.DeliveryStatus IN ('DELIVERED', 'INCOMPLETE')

        GROUP BY
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryDateTime,
            d.DeliveryStatus,
            o.CustomerID,
            c.CustomerName,
            oi.OrderItemID,
            b.BottleTypeID,
            bt.BottleType

        HAVING
            COUNT(DISTINCT odt.BottleID) >
            COUNT(
                DISTINCT CASE
                    WHEN dpt.BottleID IS NOT NULL
                    THEN odt.BottleID
                END
            )

        ORDER BY
            d.DeliveryDateTime ASC,
            d.DeliveryID ASC,
            b.BottleTypeID ASC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute([':accId' => $accId]);

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    /*
     * Combine bottle-type rows into one delivery record.
     */
    $deliveries = [];

    foreach ($rows as $row) {
        $deliveryId = (int) $row['DeliveryID'];

        if (!isset($deliveries[$deliveryId])) {
            $deliveries[$deliveryId] = [
                'DeliveryID' => $deliveryId,
                'OrderID' => (int) $row['OrderID'],
                'AccID' => (int) $row['AccID'],
                'DeliveryDateTime' => $row['DeliveryDateTime'],
                'DeliveryStatus' => $row['DeliveryStatus'],
                'CustomerID' => (int) $row['CustomerID'],
                'CustomerName' => $row['CustomerName'],
                'BottleTypes' => [],
                'DeliveredBottleCount' => 0,
                'PickedUpBottleCount' => 0,
                'RemainingBottleCount' => 0
            ];
        }

        $delivered = (int) $row['DeliveredBottleCount'];
        $pickedUp = (int) $row['PickedUpBottleCount'];
        $remaining = (int) $row['RemainingBottleCount'];

        $deliveries[$deliveryId]['BottleTypes'][] = [
            'BottleTypeID' => (int) $row['BottleTypeID'],
            'BottleType' => $row['BottleType'],
            'DeliveredBottleCount' => $delivered,
            'PickedUpBottleCount' => $pickedUp,
            'RemainingBottleCount' => $remaining
        ];

        $deliveries[$deliveryId]['DeliveredBottleCount'] += $delivered;
        $deliveries[$deliveryId]['PickedUpBottleCount'] += $pickedUp;
        $deliveries[$deliveryId]['RemainingBottleCount'] += $remaining;
    }

    echo json_encode([
        'success' => true,
        'data' => array_values($deliveries)
    ]);

} catch (PDOException $e) {
    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Unable to retrieve pickup orders.'
    ]);
}

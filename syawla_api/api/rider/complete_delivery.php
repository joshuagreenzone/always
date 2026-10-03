<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

function respond(int $status, array $payload): void
{
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

try {
    $database = new Database();
    $db = $database->connect();

    $input = json_decode(file_get_contents('php://input'), true);

    if (!is_array($input)) {
        respond(400, [
            'success' => false,
            'message' => 'Invalid JSON request.'
        ]);
    }

    $accId = (int) ($input['accId'] ?? 0);
    $orderId = (int) ($input['orderId'] ?? 0);
    $deliveryId = (int) ($input['deliveryId'] ?? 0);
    $bottles = $input['bottles'] ?? [];
    $incompleteReason = trim(
        (string) ($input['incompleteReason'] ?? '')
    );

    if ($accId <= 0 || $orderId <= 0 || $deliveryId <= 0) {
        respond(400, [
            'success' => false,
            'message' => 'Invalid delivery information.'
        ]);
    }

    if (!is_array($bottles) || count($bottles) === 0) {
        respond(400, [
            'success' => false,
            'message' => 'Scan at least one bottle before confirming delivery.'
        ]);
    }

    if (count($bottles) > 500) {
        respond(400, [
            'success' => false,
            'message' => 'Too many bottles were submitted.'
        ]);
    }

    /*
     * Validate bottle request structure and duplicate numbers.
     */
    $seenBottleNumbers = [];

    foreach ($bottles as $index => $item) {
        if (!is_array($item)) {
            respond(400, [
                'success' => false,
                'message' => 'Invalid bottle data at index ' . $index . '.'
            ]);
        }

        $number = trim((string) ($item['bottleNumber'] ?? ''));

        if ($number === '') {
            respond(400, [
                'success' => false,
                'message' => 'A bottle number is missing.'
            ]);
        }

        $normalized = strtolower($number);

        if (isset($seenBottleNumbers[$normalized])) {
            respond(400, [
                'success' => false,
                'message' => 'Duplicate bottle detected: ' . $number
            ]);
        }

        $seenBottleNumbers[$normalized] = true;
    }

    /*
     * Verify that the delivery belongs to this rider.
     */
    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,
            o.OrderStatus,
            o.PaymentStatus
        FROM delivery d
        INNER JOIN orders o ON o.OrderID = d.OrderID
        INNER JOIN accounts a ON a.AccID = d.AccID
        WHERE d.DeliveryID = :deliveryId
          AND d.OrderID = :orderId
          AND d.AccID = :accId
          AND a.AccType = 'RIDER'
        LIMIT 1
    ";

    $stmt = $db->prepare($deliverySql);
    $stmt->execute([
        ':deliveryId' => $deliveryId,
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $delivery = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$delivery) {
        respond(403, [
            'success' => false,
            'message' => 'This delivery is not assigned to this rider.'
        ]);
    }

    if ($delivery['DeliveryStatus'] === 'DELIVERED') {
        respond(400, [
            'success' => false,
            'message' => 'This delivery has already been completed.'
        ]);
    }

    if ($delivery['DeliveryStatus'] === 'INCOMPLETE') {
        respond(400, [
            'success' => false,
            'message' => 'This delivery has already been closed as incomplete.'
        ]);
    }

    if ($delivery['DeliveryStatus'] === 'CANCELLED') {
        respond(400, [
            'success' => false,
            'message' => 'This delivery has been cancelled.'
        ]);
    }

    $db->beginTransaction();

    try {
        /*
         * Lock the delivery and order to prevent concurrent completion.
         */
        $lockSql = "
            SELECT
                d.DeliveryID,
                d.DeliveryStatus,
                o.OrderStatus,
                o.PaymentStatus
            FROM delivery d
            INNER JOIN orders o ON o.OrderID = d.OrderID
            WHERE d.DeliveryID = :deliveryId
              AND d.OrderID = :orderId
              AND d.AccID = :accId
            FOR UPDATE
        ";

        $stmt = $db->prepare($lockSql);
        $stmt->execute([
            ':deliveryId' => $deliveryId,
            ':orderId' => $orderId,
            ':accId' => $accId
        ]);

        $locked = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$locked) {
            throw new Exception('Delivery could not be locked.');
        }

        if (!in_array(
            $locked['DeliveryStatus'],
            ['ASSIGNED', 'OUT_FOR_DELIVERY'],
            true
        )) {
            throw new Exception(
                'This delivery is no longer available for completion.'
            );
        }

        /*
         * Load order items.
         */
        $itemsSql = "
            SELECT
                oi.OrderItemID,
                oi.BottleTypeID,
                oi.Quantity,
                oi.UnitPrice,
                bt.BottleType
            FROM order_items oi
            INNER JOIN bottle_types bt
                ON bt.BottleTypeID = oi.BottleTypeID
            WHERE oi.OrderID = :orderId
            ORDER BY oi.OrderItemID ASC
            FOR UPDATE
        ";

        $stmt = $db->prepare($itemsSql);
        $stmt->execute([':orderId' => $orderId]);
        $orderItems = $stmt->fetchAll(PDO::FETCH_ASSOC);

        if (!$orderItems) {
            throw new Exception('This order has no order items.');
        }

        $requiredCount = 0;
        $remainingItems = [];

        foreach ($orderItems as $item) {
            $itemId = (int) $item['OrderItemID'];
            $quantity = (int) $item['Quantity'];

            if ($quantity <= 0) {
                throw new Exception(
                    'An order item has an invalid quantity.'
                );
            }

            $requiredCount += $quantity;

            $remainingItems[$itemId] = [
                'orderItemId' => $itemId,
                'bottleTypeId' => (int) $item['BottleTypeID'],
                'bottleType' => $item['BottleType'],
                'quantity' => $quantity,
                'remaining' => $quantity,
                'unitPrice' => (float) $item['UnitPrice']
            ];
        }

        $submittedCount = count($bottles);

        if ($submittedCount > $requiredCount) {
            throw new Exception(
                'The scanned bottle count exceeds the ordered quantity. '
                . 'Ordered: ' . $requiredCount
                . ', scanned: ' . $submittedCount . '.'
            );
        }

        $isIncomplete = $submittedCount < $requiredCount;

        if ($isIncomplete && $incompleteReason === '') {
            throw new Exception(
                'Please provide a reason for the incomplete delivery.'
            );
        }

        if (mb_strlen($incompleteReason) > 5000) {
            throw new Exception(
                'The incomplete-delivery reason is too long.'
            );
        }

        /*
         * Do not permit a second set of bottle transactions for this delivery.
         */
        $stmt = $db->prepare("
            SELECT COUNT(*)
            FROM order_delivery_transaction
            WHERE OrderID = :orderId
              AND DeliveryID = :deliveryId
        ");

        $stmt->execute([
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId
        ]);

        if ((int) $stmt->fetchColumn() > 0) {
            throw new Exception(
                'This delivery already has saved bottle transactions.'
            );
        }

        /*
         * Prepare bottle lookup and validation queries.
         */
        $bottleStmt = $db->prepare("
            SELECT
                b.BottleID,
                b.BottleNumber,
                b.BottleTypeID,
                bt.BottleType
            FROM bottles b
            INNER JOIN bottle_types bt
                ON bt.BottleTypeID = b.BottleTypeID
            WHERE b.BottleNumber = :bottleNumber
            LIMIT 1
            FOR UPDATE
        ");

        $activeBottleStmt = $db->prepare("
            SELECT odt.ODTID
            FROM order_delivery_transaction odt
            INNER JOIN delivery d
                ON d.DeliveryID = odt.DeliveryID
            WHERE odt.BottleID = :bottleId
              AND d.DeliveryStatus = 'DELIVERED'
              AND NOT EXISTS (
                  SELECT 1
                  FROM delivery_pickup_transaction dpt
                  INNER JOIN pickup p
                      ON p.PickUpID = dpt.PickUpID
                  WHERE dpt.BottleID = odt.BottleID
                    AND p.DeliveryID = odt.DeliveryID
                    AND p.PickUpDateTime > d.DeliveryDateTime
              )
            LIMIT 1
        ");

        $activeDeliveryStmt = $db->prepare("
            SELECT odt.ODTID
            FROM order_delivery_transaction odt
            INNER JOIN delivery d
                ON d.DeliveryID = odt.DeliveryID
            WHERE odt.BottleID = :bottleId
              AND d.DeliveryStatus IN ('ASSIGNED', 'OUT_FOR_DELIVERY')
            LIMIT 1
        ");

        $refillStmt = $db->prepare("
            SELECT RefillID, RefillDateTime
            FROM refill
            WHERE BottleID = :bottleId
            ORDER BY RefillDateTime DESC, RefillID DESC
            LIMIT 1
        ");

        $latestPickupStmt = $db->prepare("
            SELECT p.PickUpID, p.PickUpDateTime
            FROM delivery_pickup_transaction dpt
            INNER JOIN pickup p ON p.PickUpID = dpt.PickUpID
            WHERE dpt.BottleID = :bottleId
            ORDER BY p.PickUpDateTime DESC, p.PickUpID DESC
            LIMIT 1
        ");

        $insertOdtStmt = $db->prepare("
            INSERT INTO order_delivery_transaction
                (OrderID, OrderItemID, DeliveryID, BottleID)
            VALUES
                (:orderId, :orderItemId, :deliveryId, :bottleId)
        ");

        $insertScanStmt = $db->prepare("
            INSERT INTO bottle_scan_event
                (
                    BottleID,
                    AccID,
                    EventType,
                    OrderID,
                    DeliveryID,
                    ODTID,
                    ScanDateTime,
                    Latitude,
                    Longitude,
                    LocationAccuracy
                )
            VALUES
                (
                    :bottleId,
                    :accId,
                    'DELIVERY_SCAN',
                    :orderId,
                    :deliveryId,
                    :odtId,
                    CURRENT_TIMESTAMP,
                    :latitude,
                    :longitude,
                    :locationAccuracy
                )
        ");

        $confirmedBottles = [];
        $deliveredItemCounts = [];

        /*
         * Validate and save only bottles actually scanned.
         */
        foreach ($bottles as $item) {
            $bottleNumber = trim((string) $item['bottleNumber']);

            $latitude = (
                isset($item['latitude']) &&
                $item['latitude'] !== ''
            ) ? (float) $item['latitude'] : null;

            $longitude = (
                isset($item['longitude']) &&
                $item['longitude'] !== ''
            ) ? (float) $item['longitude'] : null;

            $accuracy = (
                isset($item['accuracy']) &&
                $item['accuracy'] !== ''
            ) ? (float) $item['accuracy'] : null;

            if (
                ($latitude !== null && ($latitude < -90 || $latitude > 90)) ||
                ($longitude !== null && ($longitude < -180 || $longitude > 180)) ||
                ($accuracy !== null && $accuracy < 0)
            ) {
                throw new Exception(
                    'Invalid GPS information for bottle ' . $bottleNumber . '.'
                );
            }

            $bottleStmt->execute([
                ':bottleNumber' => $bottleNumber
            ]);

            $bottle = $bottleStmt->fetch(PDO::FETCH_ASSOC);

            if (!$bottle) {
                throw new Exception('Bottle not found: ' . $bottleNumber);
            }

            $bottleId = (int) $bottle['BottleID'];
            $bottleTypeId = (int) $bottle['BottleTypeID'];

            /*
             * Match the bottle to an order item with remaining quantity.
             */
            $matchedOrderItemId = null;

            foreach ($remainingItems as $itemId => &$remainingItem) {
                if (
                    $remainingItem['bottleTypeId'] === $bottleTypeId &&
                    $remainingItem['remaining'] > 0
                ) {
                    $matchedOrderItemId = (int) $itemId;
                    $remainingItem['remaining']--;
                    break;
                }
            }

            unset($remainingItem);

            if ($matchedOrderItemId === null) {
                throw new Exception(
                    'Bottle ' . $bottleNumber
                    . ' (' . $bottle['BottleType'] . ') '
                    . 'does not match any remaining order quantity.'
                );
            }

            $activeBottleStmt->execute([':bottleId' => $bottleId]);

            if ($activeBottleStmt->fetch()) {
                throw new Exception(
                    'Bottle ' . $bottleNumber
                    . ' has already been delivered to another customer '
                    . 'and has not been picked up.'
                );
            }

            $activeDeliveryStmt->execute([':bottleId' => $bottleId]);

            if ($activeDeliveryStmt->fetch()) {
                throw new Exception(
                    'Bottle ' . $bottleNumber
                    . ' is assigned to another active delivery.'
                );
            }

            $refillStmt->execute([':bottleId' => $bottleId]);
            $latestRefill = $refillStmt->fetch(PDO::FETCH_ASSOC);

            if (!$latestRefill) {
                throw new Exception(
                    'Bottle ' . $bottleNumber . ' has not been refilled.'
                );
            }

            $latestPickupStmt->execute([':bottleId' => $bottleId]);
            $latestPickup = $latestPickupStmt->fetch(PDO::FETCH_ASSOC);

            if (
                $latestPickup &&
                strtotime($latestRefill['RefillDateTime']) <=
                    strtotime($latestPickup['PickUpDateTime'])
            ) {
                throw new Exception(
                    'Bottle ' . $bottleNumber
                    . ' has been picked up but not refilled afterward.'
                );
            }

            $insertOdtStmt->execute([
                ':orderId' => $orderId,
                ':orderItemId' => $matchedOrderItemId,
                ':deliveryId' => $deliveryId,
                ':bottleId' => $bottleId
            ]);

            $odtId = (int) $db->lastInsertId();

            $insertScanStmt->execute([
                ':bottleId' => $bottleId,
                ':accId' => $accId,
                ':orderId' => $orderId,
                ':deliveryId' => $deliveryId,
                ':odtId' => $odtId,
                ':latitude' => $latitude,
                ':longitude' => $longitude,
                ':locationAccuracy' => $accuracy
            ]);

            $confirmedBottles[] = [
                'bottleId' => $bottleId,
                'bottleNumber' => $bottle['BottleNumber'],
                'bottleTypeId' => $bottleTypeId,
                'bottleType' => $bottle['BottleType'],
                'orderItemId' => $matchedOrderItemId,
                'odtId' => $odtId,
                'scanEventId' => (int) $db->lastInsertId()
            ];

            if (!isset($deliveredItemCounts[$matchedOrderItemId])) {
                $deliveredItemCounts[$matchedOrderItemId] = 0;
            }

            $deliveredItemCounts[$matchedOrderItemId]++;
        }

        /*
         * Verify saved delivery records against the scanned count.
         */
        $stmt = $db->prepare("
            SELECT COUNT(*)
            FROM order_delivery_transaction
            WHERE OrderID = :orderId
              AND DeliveryID = :deliveryId
        ");

        $stmt->execute([
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId
        ]);

        $finalCount = (int) $stmt->fetchColumn();

        if ($finalCount !== $submittedCount) {
            throw new Exception(
                'The saved bottle count does not match the scanned count.'
            );
        }

        /*
         * Check the per-item counts do not exceed ordered quantities.
         */
        foreach ($deliveredItemCounts as $itemId => $count) {
            if ($count > $remainingItems[$itemId]['quantity']) {
                throw new Exception(
                    'Delivered quantity exceeds the ordered quantity '
                    . 'for order item ' . $itemId . '.'
                );
            }
        }

        /*
         * Close the delivery. Undelivered bottles are not inserted.
         */
        $deliveryStatus = $isIncomplete ? 'INCOMPLETE' : 'DELIVERED';
        $orderStatus = $isIncomplete ? 'INCOMPLETE' : 'DELIVERED';

        $updateDeliveryStmt = $db->prepare("
            UPDATE delivery
            SET
                DeliveryStatus = :deliveryStatus,
                DeliveryDateTime = NOW(),
                IncompleteReason = :incompleteReason
            WHERE DeliveryID = :deliveryId
              AND OrderID = :orderId
              AND AccID = :accId
        ");

        $updateDeliveryStmt->execute([
            ':deliveryStatus' => $deliveryStatus,
            ':incompleteReason' => $isIncomplete
                ? $incompleteReason
                : null,
            ':deliveryId' => $deliveryId,
            ':orderId' => $orderId,
            ':accId' => $accId
        ]);

        $updateOrderStmt = $db->prepare("
            UPDATE orders
            SET OrderStatus = :orderStatus
            WHERE OrderID = :orderId
        ");

        $updateOrderStmt->execute([
            ':orderStatus' => $orderStatus,
            ':orderId' => $orderId
        ]);

        $db->commit();

        respond(200, [
            'success' => true,
            'message' => $isIncomplete
                ? 'Incomplete delivery recorded successfully.'
                : 'Delivery completed successfully.',
            'data' => [
                'orderId' => $orderId,
                'deliveryId' => $deliveryId,
                'deliveryStatus' => $deliveryStatus,
                'orderStatus' => $orderStatus,
                'paymentStatus' => $locked['PaymentStatus'],
                'requiredQuantity' => $requiredCount,
                'scannedQuantity' => $finalCount,
                'undeliveredQuantity' => $requiredCount - $finalCount,
                'incompleteReason' => $isIncomplete
                    ? $incompleteReason
                    : null,
                'bottles' => $confirmedBottles
            ]
        ]);
    } catch (Throwable $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }

        respond(400, [
            'success' => false,
            'message' => $e->getMessage()
        ]);
    }
} catch (PDOException $e) {
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }

    respond(500, [
        'success' => false,
        'message' => 'Database error.'
    ]);
}
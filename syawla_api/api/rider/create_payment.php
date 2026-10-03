
<?php

header('Content-Type: application/json; charset=utf-8');

require_once '../../config/database.php';

$db = null;

function respond(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body);
    exit;
}

function rollbackIfNeeded(?PDO $db): void
{
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }
}

try {
    $database = new Database();
    $db = $database->connect();
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    /*
     * Read multipart/form-data request.
     */
    $accId = (int)($_POST['accId'] ?? 0);
    $orderId = (int)($_POST['orderId'] ?? 0);
    $paymentAmount = filter_var(
        $_POST['paymentAmount'] ?? null,
        FILTER_VALIDATE_FLOAT
    );
    $paymentType = strtoupper(trim($_POST['paymentType'] ?? ''));
    $notes = trim($_POST['notes'] ?? '');

    if ($accId <= 0 || $orderId <= 0) {
        respond(400, [
            'success' => false,
            'message' => 'Invalid account or order.'
        ]);
    }

    if (
        $paymentAmount === false ||
        !is_finite((float)$paymentAmount) ||
        (float)$paymentAmount <= 0
    ) {
        respond(400, [
            'success' => false,
            'message' => 'Payment amount must be greater than zero.'
        ]);
    }

    $paymentAmount = round((float)$paymentAmount, 2);

    $allowedPaymentTypes = ['CASH', 'GCASH', 'BANK_TRANSFER'];

    if (!in_array($paymentType, $allowedPaymentTypes, true)) {
        respond(400, [
            'success' => false,
            'message' => 'Invalid payment method.'
        ]);
    }

    /*
     * Validate receiving account.
     */
    $stmt = $db->prepare("
        SELECT AccID, AccName, AccType
        FROM accounts
        WHERE AccID = :accId
        LIMIT 1
    ");
    $stmt->execute([':accId' => $accId]);
    $account = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$account) {
        respond(403, [
            'success' => false,
            'message' => 'Account not found.'
        ]);
    }

    if (!in_array($account['AccType'], ['ADMIN', 'RIDER'], true)) {
        respond(403, [
            'success' => false,
            'message' => 'This account is not authorized to receive payments.'
        ]);
    }

    /*
     * Receipt requirements:
     * CASH: optional.
     * GCASH / BANK_TRANSFER: required.
     */
    $receiptImage = null;

    if ($paymentType !== 'CASH') {
        if (
            !isset($_FILES['receiptImage']) ||
            $_FILES['receiptImage']['error'] !== UPLOAD_ERR_OK
        ) {
            respond(400, [
                'success' => false,
                'message' => 'Payment receipt photo is required.'
            ]);
        }

        if ($_FILES['receiptImage']['size'] > 5 * 1024 * 1024) {
            respond(400, [
                'success' => false,
                'message' => 'Receipt image must not exceed 5 MB.'
            ]);
        }

        $tmpFile = $_FILES['receiptImage']['tmp_name'];

        if (!is_uploaded_file($tmpFile)) {
            respond(400, [
                'success' => false,
                'message' => 'Invalid receipt upload.'
            ]);
        }

        $mimeType = mime_content_type($tmpFile);
        $allowedMimeTypes = [
            'image/jpeg',
            'image/png',
            'image/webp'
        ];

        if (!in_array($mimeType, $allowedMimeTypes, true)) {
            respond(400, [
                'success' => false,
                'message' => 'Receipt must be a JPG, PNG, or WEBP image.'
            ]);
        }

        $receiptImage = file_get_contents($tmpFile);

        if ($receiptImage === false) {
            respond(500, [
                'success' => false,
                'message' => 'Unable to read receipt image.'
            ]);
        }
    }

    $db->beginTransaction();

    /*
     * Lock the order so simultaneous payment requests cannot
     * both use the same outstanding balance.
     */
    $stmt = $db->prepare("
        SELECT
            OrderID,
            CustomerID,
            OrderStatus,
            PaymentStatus
        FROM orders
        WHERE OrderID = :orderId
        LIMIT 1
        FOR UPDATE
    ");
    $stmt->execute([':orderId' => $orderId]);
    $order = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$order) {
        rollbackIfNeeded($db);
        respond(404, [
            'success' => false,
            'message' => 'Order not found.'
        ]);
    }

    /*
     * For riders, require an assigned delivery.
     * Payment is accepted only after delivery has been closed.
     */
    if ($account['AccType'] === 'RIDER') {
        $stmt = $db->prepare("
            SELECT DeliveryID, DeliveryStatus
            FROM delivery
            WHERE OrderID = :orderId
              AND AccID = :accId
            LIMIT 1
            FOR UPDATE
        ");
        $stmt->execute([
            ':orderId' => $orderId,
            ':accId' => $accId
        ]);
        $delivery = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$delivery) {
            rollbackIfNeeded($db);
            respond(403, [
                'success' => false,
                'message' => 'This order is not assigned to this rider.'
            ]);
        }

        if (!in_array(
            $delivery['DeliveryStatus'],
            ['DELIVERED', 'INCOMPLETE'],
            true
        )) {
            rollbackIfNeeded($db);
            respond(400, [
                'success' => false,
                'message' => 'Complete and close the delivery before recording payment.'
            ]);
        }
    }

    /*
     * Load order items and their quantity limits.
     * UnitPrice is the price to use for each delivered bottle.
     */
    $stmt = $db->prepare("
        SELECT
            OrderItemID,
            BottleTypeID,
            Quantity,
            UnitPrice
        FROM order_items
        WHERE OrderID = :orderId
        ORDER BY OrderItemID ASC
        FOR UPDATE
    ");
    $stmt->execute([':orderId' => $orderId]);
    $orderItems = $stmt->fetchAll(PDO::FETCH_ASSOC);

    /*
     * Support legacy orders that have no order_items rows.
     * The orders table has one BottleTypeID, Quantity, and UnitPrice.
     */
    if (!$orderItems) {
        $stmt = $db->prepare("
            SELECT BottleTypeID, Quantity, UnitPrice
            FROM orders
            WHERE OrderID = :orderId
            LIMIT 1
        ");
        $stmt->execute([':orderId' => $orderId]);
        $legacyItem = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$legacyItem) {
            rollbackIfNeeded($db);
            respond(400, [
                'success' => false,
                'message' => 'No order items were found.'
            ]);
        }

        $orderItems = [[
            'OrderItemID' => null,
            'BottleTypeID' => $legacyItem['BottleTypeID'],
            'Quantity' => $legacyItem['Quantity'],
            'UnitPrice' => $legacyItem['UnitPrice']
        ]];
    }

    /*
     * Build item allocation counters.
     */
    $itemsById = [];
    $itemsByType = [];

    foreach ($orderItems as $index => $item) {
        $item['OrderItemID'] = $item['OrderItemID'] === null
            ? null
            : (int)$item['OrderItemID'];
        $item['BottleTypeID'] = (int)$item['BottleTypeID'];
        $item['Quantity'] = (int)$item['Quantity'];
        $item['UnitPrice'] = round((float)$item['UnitPrice'], 2);
        $item['DeliveredCount'] = 0;

        $orderItems[$index] = $item;

        if ($item['OrderItemID'] !== null) {
            $itemsById[$item['OrderItemID']] = $index;
        }

        $itemsByType[$item['BottleTypeID']][] = $index;
    }

    /*
     * Read actual delivery records and match each bottle to its
     * order item. A NULL OrderItemID can be matched by bottle type,
     * but only while that item's ordered quantity has capacity.
     */
    $stmt = $db->prepare("
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.OrderItemID,
            odt.DeliveryID,
            odt.BottleID,
            b.BottleTypeID
        FROM order_delivery_transaction odt
        INNER JOIN bottles b
            ON b.BottleID = odt.BottleID
        WHERE odt.OrderID = :orderId
        ORDER BY odt.ODTID ASC
        FOR UPDATE
    ");
    $stmt->execute([':orderId' => $orderId]);
    $deliveredRows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $deliveredQuantity = 0;
    $deliveredAmount = 0.00;
    $unmatchedBottles = [];

    foreach ($deliveredRows as $row) {
        $bottleTypeId = (int)$row['BottleTypeID'];
        $itemIndex = null;

        if ($row['OrderItemID'] !== null) {
            $itemId = (int)$row['OrderItemID'];

            if (!isset($itemsById[$itemId])) {
                $unmatchedBottles[] = (int)$row['BottleID'];
                continue;
            }

            $itemIndex = $itemsById[$itemId];

            if (
                $orderItems[$itemIndex]['BottleTypeID'] !== $bottleTypeId ||
                $orderItems[$itemIndex]['DeliveredCount'] >=
                    $orderItems[$itemIndex]['Quantity']
            ) {
                $unmatchedBottles[] = (int)$row['BottleID'];
                continue;
            }
        } else {
            if (!isset($itemsByType[$bottleTypeId])) {
                $unmatchedBottles[] = (int)$row['BottleID'];
                continue;
            }

            foreach ($itemsByType[$bottleTypeId] as $candidateIndex) {
                if (
                    $orderItems[$candidateIndex]['DeliveredCount'] <
                    $orderItems[$candidateIndex]['Quantity']
                ) {
                    $itemIndex = $candidateIndex;
                    break;
                }
            }

            if ($itemIndex === null) {
                $unmatchedBottles[] = (int)$row['BottleID'];
                continue;
            }
        }

        $orderItems[$itemIndex]['DeliveredCount']++;
        $deliveredQuantity++;
        $deliveredAmount += $orderItems[$itemIndex]['UnitPrice'];
    }

    if ($unmatchedBottles) {
        rollbackIfNeeded($db);
        respond(409, [
            'success' => false,
            'message' =>
                'Some delivered bottles cannot be matched safely to the order items. Correct the delivery records before taking payment.',
            'data' => [
                'orderId' => $orderId,
                'unmatchedBottleIds' => $unmatchedBottles
            ]
        ]);
    }

    $deliveredAmount = round($deliveredAmount, 2);

    if ($deliveredQuantity <= 0 || $deliveredAmount <= 0) {
        rollbackIfNeeded($db);
        respond(400, [
            'success' => false,
            'message' => 'No delivered bottles with a valid amount were found for this order.',
            'data' => [
                'orderId' => $orderId,
                'deliveredQuantity' => $deliveredQuantity,
                'deliveredAmount' => $deliveredAmount
            ]
        ]);
    }

    /*
     * Sum payments already allocated to this order.
     * Use transaction Amount, not PaymentAmount, because a
     * payment can be allocated across multiple orders.
     */
    $stmt = $db->prepare("
        SELECT COALESCE(SUM(Amount), 0) AS PaidAmount
        FROM order_payment_transaction
        WHERE OrderID = :orderId
        FOR UPDATE
    ");
    $stmt->execute([':orderId' => $orderId]);
    $alreadyPaid = round(
        (float)$stmt->fetchColumn(),
        2
    );

    $outstanding = round($deliveredAmount - $alreadyPaid, 2);

    if ($outstanding <= 0.00) {
        /*
         * Do not create another payment when the delivered
         * value is already covered by recorded payments.
         */
        $db->commit();

        respond(409, [
            'success' => false,
            'message' =>
                'This order has no outstanding balance for the delivered bottles.',
            'data' => [
                'orderId' => $orderId,
                'deliveredQuantity' => $deliveredQuantity,
                'totalAmount' => $deliveredAmount,
                'paidAmount' => $alreadyPaid,
                'outstandingAmount' => 0,
                'paymentStatus' => 'PAID'
            ]
        ]);
    }

    if ($paymentAmount > $outstanding) {
        rollbackIfNeeded($db);
        respond(400, [
            'success' => false,
            'message' => 'Payment exceeds the outstanding balance.',
            'data' => [
                'totalAmount' => $deliveredAmount,
                'deliveredQuantity' => $deliveredQuantity,
                'paidAmount' => $alreadyPaid,
                'outstandingAmount' => $outstanding,
                'paymentStatus' => $alreadyPaid > 0
                    ? 'PARTIALLY_PAID'
                    : 'UNPAID'
            ]
        ]);
    }

    /*
     * Insert payment record.
     */
    $stmt = $db->prepare("
        INSERT INTO payments (
            CustomerID,
            AccID,
            PaymentAmount,
            PaymentType,
            PaymentDateTime,
            ReceiptImage,
            Notes
        ) VALUES (
            :customerId,
            :accId,
            :paymentAmount,
            :paymentType,
            NOW(),
            :receiptImage,
            :notes
        )
    ");

    $stmt->bindValue(':customerId', (int)$order['CustomerID'], PDO::PARAM_INT);
    $stmt->bindValue(':accId', $accId, PDO::PARAM_INT);
    $stmt->bindValue(':paymentAmount', $paymentAmount);
    $stmt->bindValue(':paymentType', $paymentType);

    if ($receiptImage === null) {
        $stmt->bindValue(':receiptImage', null, PDO::PARAM_NULL);
    } else {
        $stmt->bindValue(':receiptImage', $receiptImage, PDO::PARAM_LOB);
    }

    $stmt->bindValue(
        ':notes',
        $notes === '' ? null : $notes,
        $notes === '' ? PDO::PARAM_NULL : PDO::PARAM_STR
    );

    $stmt->execute();
    $paymentId = (int)$db->lastInsertId();

    /*
     * Link the payment to the order.
     */
    $stmt = $db->prepare("
        INSERT INTO order_payment_transaction (
            OrderID,
            PaymentID,
            Amount
        ) VALUES (
            :orderId,
            :paymentId,
            :amount
        )
    ");

    $stmt->execute([
        ':orderId' => $orderId,
        ':paymentId' => $paymentId,
        ':amount' => $paymentAmount
    ]);

    /*
     * Update payment status based on the delivered value.
     * Do not change OrderStatus: INCOMPLETE must remain INCOMPLETE.
     */
    $newPaidAmount = round($alreadyPaid + $paymentAmount, 2);
    $newOutstanding = round($deliveredAmount - $newPaidAmount, 2);

    $paymentStatus = $newOutstanding <= 0.00
        ? 'PAID'
        : 'PARTIALLY_PAID';

    $stmt = $db->prepare("
        UPDATE orders
        SET PaymentStatus = :paymentStatus
        WHERE OrderID = :orderId
    ");

    $stmt->execute([
        ':paymentStatus' => $paymentStatus,
        ':orderId' => $orderId
    ]);

    $db->commit();

    respond(200, [
        'success' => true,
        'message' => 'Payment recorded successfully.',
        'data' => [
            'paymentId' => $paymentId,
            'orderId' => $orderId,
            'deliveredQuantity' => $deliveredQuantity,
            'totalAmount' => $deliveredAmount,
            'paidAmount' => $newPaidAmount,
            'outstandingAmount' => max(0, $newOutstanding),
            'paymentStatus' => $paymentStatus,
            'receivedByAccId' => $accId,
            'receivedByType' => $account['AccType']
        ]
    ]);

} catch (PDOException $e) {
    rollbackIfNeeded($db);

    error_log(
        'Syawla create_payment.php database error: ' .
        $e->getMessage()
    );

    respond(500, [
        'success' => false,
        'message' => 'Database error while processing payment.'
    ]);

} catch (Throwable $e) {
    rollbackIfNeeded($db);

    error_log(
        'Syawla create_payment.php error: ' . $e->getMessage()
    );

    respond(500, [
        'success' => false,
        'message' => 'Unable to process payment.'
    ]);
}
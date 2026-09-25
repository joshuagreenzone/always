<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * Multipart/form-data
     */
    $accId = isset($_POST['accId'])
        ? (int) $_POST['accId']
        : 0;

    $orderId = isset($_POST['orderId'])
        ? (int) $_POST['orderId']
        : 0;

    $paymentAmount = isset($_POST['paymentAmount'])
        ? (float) $_POST['paymentAmount']
        : 0;

    $paymentType = isset($_POST['paymentType'])
        ? trim($_POST['paymentType'])
        : '';

    $notes = isset($_POST['notes'])
        ? trim($_POST['notes'])
        : '';

    if ($accId <= 0 || $orderId <= 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid account or order.'
        ]);

        exit;
    }

    if ($paymentAmount <= 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Payment amount must be greater than zero.'
        ]);

        exit;
    }

    $allowedPaymentTypes = [
        'CASH',
        'GCASH',
        'BANK_TRANSFER'
    ];

    if (!in_array(
        $paymentType,
        $allowedPaymentTypes,
        true
    )) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid payment method.'
        ]);

        exit;
    }

    /*
     * Validate receiving account.
     */
    $accountSql = "
        SELECT
            AccID,
            AccName,
            AccType
        FROM accounts
        WHERE AccID = :accId
        LIMIT 1
    ";

    $accountStmt = $db->prepare($accountSql);

    $accountStmt->execute([
        ':accId' => $accId
    ]);

    $account = $accountStmt->fetch();

    if (!$account) {
        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' => 'Account not found.'
        ]);

        exit;
    }

    if (
        $account['AccType'] !== 'ADMIN' &&
        $account['AccType'] !== 'RIDER'
    ) {
        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' =>
                'This account is not authorized to receive payments.'
        ]);

        exit;
    }

    /*
     * Verify order.
     */
    $orderSql = "
        SELECT
            o.OrderID,
            o.CustomerID,
            o.Quantity,
            o.UnitPrice,
            (o.Quantity * o.UnitPrice) AS TotalAmount
        FROM orders o
        WHERE o.OrderID = :orderId
        LIMIT 1
    ";

    $orderStmt = $db->prepare($orderSql);

    $orderStmt->execute([
        ':orderId' => $orderId
    ]);

    $order = $orderStmt->fetch();

    if (!$order) {
        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' => 'Order not found.'
        ]);

        exit;
    }

    /*
     * Rider can only receive payment for their own delivery.
     */
    if ($account['AccType'] === 'RIDER') {

        $deliverySql = "
            SELECT DeliveryID
            FROM delivery
            WHERE OrderID = :orderId
              AND AccID = :accId
            LIMIT 1
        ";

        $deliveryStmt = $db->prepare($deliverySql);

        $deliveryStmt->execute([
            ':orderId' => $orderId,
            ':accId' => $accId
        ]);

        $delivery = $deliveryStmt->fetch();

        if (!$delivery) {
            http_response_code(403);

            echo json_encode([
                'success' => false,
                'message' =>
                    'This order is not assigned to this rider.'
            ]);

            exit;
        }
    }

    /*
     * Calculate current payment total.
     */
    $paidSql = "
        SELECT
            COALESCE(SUM(opt.Amount), 0) AS PaidAmount
        FROM order_payment_transaction opt
        INNER JOIN payments p
            ON opt.PaymentID = p.PaymentID
        WHERE opt.OrderID = :orderId
    ";

    $paidStmt = $db->prepare($paidSql);

    $paidStmt->execute([
        ':orderId' => $orderId
    ]);

    $paid = $paidStmt->fetch();

    $totalAmount = (float) $order['TotalAmount'];
    $alreadyPaid = (float) $paid['PaidAmount'];

    $outstanding = $totalAmount - $alreadyPaid;

    if ($paymentAmount > $outstanding + 0.00001) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Payment exceeds the outstanding balance.'
        ]);

        exit;
    }

    /*
     * Receipt image.
     *
     * Cash does NOT require an image.
     * GCash and Bank Transfer DO require an image.
     */
    $receiptImage = null;

    if ($paymentType !== 'CASH') {

        if (
            !isset($_FILES['receiptImage']) ||
            $_FILES['receiptImage']['error'] !==
                UPLOAD_ERR_OK
        ) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Payment receipt photo is required.'
            ]);

            exit;
        }

        if ($_FILES['receiptImage']['size'] > 5 * 1024 * 1024) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Receipt image must not exceed 5 MB.'
            ]);

            exit;
        }

        $mimeType = mime_content_type(
            $_FILES['receiptImage']['tmp_name']
        );

        $allowedMimeTypes = [
            'image/jpeg',
            'image/png',
            'image/webp'
        ];

        if (!in_array(
            $mimeType,
            $allowedMimeTypes,
            true
        )) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Invalid receipt image.'
            ]);

            exit;
        }

        $receiptImage = file_get_contents(
            $_FILES['receiptImage']['tmp_name']
        );

        if ($receiptImage === false) {
            http_response_code(500);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Unable to read receipt image.'
            ]);

            exit;
        }
    }

    $db->beginTransaction();

    /*
     * Create payment.
     */
    $paymentSql = "
        INSERT INTO payments
        (
            CustomerID,
            AccID,
            PaymentAmount,
            PaymentType,
            PaymentDateTime,
            ReceiptImage,
            Notes
        )
        VALUES
        (
            :customerId,
            :accId,
            :paymentAmount,
            :paymentType,
            NOW(),
            :receiptImage,
            :notes
        )
    ";

    $paymentStmt = $db->prepare($paymentSql);

    $paymentStmt->bindValue(
        ':customerId',
        (int) $order['CustomerID'],
        PDO::PARAM_INT
    );

    $paymentStmt->bindValue(
        ':accId',
        $accId,
        PDO::PARAM_INT
    );

    $paymentStmt->bindValue(
        ':paymentAmount',
        $paymentAmount
    );

    $paymentStmt->bindValue(
        ':paymentType',
        $paymentType
    );

    if ($receiptImage === null) {
        $paymentStmt->bindValue(
            ':receiptImage',
            null,
            PDO::PARAM_NULL
        );
    } else {
        $paymentStmt->bindValue(
            ':receiptImage',
            $receiptImage,
            PDO::PARAM_LOB
        );
    }

    if ($notes === '') {
        $paymentStmt->bindValue(
            ':notes',
            null,
            PDO::PARAM_NULL
        );
    } else {
        $paymentStmt->bindValue(
            ':notes',
            $notes
        );
    }

    $paymentStmt->execute();

    $paymentId = (int) $db->lastInsertId();

    /*
     * Link payment to order.
     */
    $transactionSql = "
        INSERT INTO order_payment_transaction
        (
            OrderID,
            PaymentID,
            Amount
        )
        VALUES
        (
            :orderId,
            :paymentId,
            :amount
        )
    ";

    $transactionStmt = $db->prepare($transactionSql);

    $transactionStmt->execute([
        ':orderId' => $orderId,
        ':paymentId' => $paymentId,
        ':amount' => $paymentAmount
    ]);

    /*
     * Calculate new payment status.
     */
    $newPaidAmount =
        $alreadyPaid + $paymentAmount;

    $newOutstanding =
        $totalAmount - $newPaidAmount;

    if ($newOutstanding <= 0.00001) {
        $paymentStatus = 'PAID';
        $newOutstanding = 0;
    } elseif ($newPaidAmount > 0) {
        $paymentStatus = 'PARTIAL';
    } else {
        $paymentStatus = 'UNPAID';
    }

    /*
     * Update order payment status.
     */
    $updateOrderSql = "
        UPDATE orders
        SET PaymentStatus = :paymentStatus
        WHERE OrderID = :orderId
    ";

    $updateOrderStmt = $db->prepare(
        $updateOrderSql
    );

    $updateOrderStmt->execute([
        ':paymentStatus' => $paymentStatus,
        ':orderId' => $orderId
    ]);

    $db->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Payment recorded successfully.',
        'data' => [
            'paymentId' => $paymentId,
            'totalAmount' => $totalAmount,
            'paidAmount' => $newPaidAmount,
            'outstandingAmount' => $newOutstanding,
            'paymentStatus' => $paymentStatus,
            'receivedByAccId' => $accId,
            'receivedByType' => $account['AccType']
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
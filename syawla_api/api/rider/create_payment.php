
<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * =========================================================
     * READ REQUEST
     * =========================================================
     *
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

    /*
     * =========================================================
     * BASIC VALIDATION
     * =========================================================
     */

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

    /*
     * =========================================================
     * NORMALIZE PAYMENT AMOUNT
     * =========================================================
     */

    $paymentAmount = round($paymentAmount, 2);

    /*
     * =========================================================
     * VALID PAYMENT TYPES
     * =========================================================
     */

    $allowedPaymentTypes = [
        'CASH',
        'GCASH',
        'BANK_TRANSFER'
    ];

    if (!in_array($paymentType, $allowedPaymentTypes, true)) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid payment method.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * VALIDATE RECEIVING ACCOUNT
     * =========================================================
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

    $account = $accountStmt->fetch(PDO::FETCH_ASSOC);

    if (!$account) {

        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' => 'Account not found.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * ONLY ADMIN AND RIDER MAY RECEIVE PAYMENTS
     * =========================================================
     */

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
     * =========================================================
     * RECEIPT IMAGE
     * =========================================================
     *
     * CASH:
     *     receipt image optional.
     *
     * GCASH / BANK_TRANSFER:
     *     receipt image required.
     */

    $receiptImage = null;

    if ($paymentType !== 'CASH') {

        if (
            !isset($_FILES['receiptImage']) ||
            $_FILES['receiptImage']['error'] !== UPLOAD_ERR_OK
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Payment receipt photo is required.'
            ]);

            exit;
        }

        if (
            $_FILES['receiptImage']['size'] >
            5 * 1024 * 1024
        ) {

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

    /*
     * =========================================================
     * BEGIN TRANSACTION
     * =========================================================
     *
     * The order row is locked so simultaneous payment requests
     * cannot spend the same outstanding balance.
     */

    $db->beginTransaction();

    /*
     * =========================================================
     * LOCK AND RETRIEVE ORDER
     * =========================================================
     *
     * IMPORTANT:
     *
     * The old implementation calculated:
     *
     *     orders.Quantity * orders.UnitPrice
     *
     * That only works for single-item orders.
     *
     * The current system supports multiple bottle types per order,
     * so order_items is now the source of truth for the order total.
     */

    $orderSql = "
        SELECT
            o.OrderID,
            o.CustomerID,
            o.PaymentStatus
        FROM orders o
        WHERE o.OrderID = :orderId
        LIMIT 1
        FOR UPDATE
    ";

    $orderStmt = $db->prepare($orderSql);

    $orderStmt->execute([
        ':orderId' => $orderId
    ]);

    $order = $orderStmt->fetch(PDO::FETCH_ASSOC);

    if (!$order) {

        $db->rollBack();

        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' => 'Order not found.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * GET ORDER TOTAL FROM ORDER ITEMS
     * =========================================================
     *
     * Example:
     *
     * 2 × Round Gallon  @ ₱50 = ₱100
     * 1 × Wilkins Gallon @ ₱60 = ₱60
     *
     * Total = ₱160
     */

    $totalSql = "
        SELECT
            COALESCE(
                SUM(
                    oi.Quantity * oi.UnitPrice
                ),
                0
            ) AS TotalAmount
        FROM order_items oi
        WHERE oi.OrderID = :orderId
    ";

    $totalStmt = $db->prepare($totalSql);

    $totalStmt->execute([
        ':orderId' => $orderId
    ]);

    $totalResult = $totalStmt->fetch(PDO::FETCH_ASSOC);

    $totalAmount = round(
        (float) ($totalResult['TotalAmount'] ?? 0),
        2
    );

    /*
     * =========================================================
     * VERIFY ORDER HAS ITEMS
     * =========================================================
     */

    if ($totalAmount <= 0) {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This order has no valid order items or has a zero total amount.',
            'data' => [
                'orderId' => $orderId,
                'totalAmount' => $totalAmount
            ]
        ]);

        exit;
    }

    /*
     * =========================================================
     * RIDER AUTHORIZATION
     * =========================================================
     *
     * A rider must have a delivery assignment for this order.
     */

    if ($account['AccType'] === 'RIDER') {

        $deliverySql = "
            SELECT
                DeliveryID,
                DeliveryStatus
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

        $delivery = $deliveryStmt->fetch(PDO::FETCH_ASSOC);

        if (!$delivery) {

            $db->rollBack();

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
     * =========================================================
     * CALCULATE PREVIOUS PAYMENTS
     * =========================================================
     *
     * Only payments linked through order_payment_transaction
     * are counted toward this order.
     */

    $paidSql = "
        SELECT
            COALESCE(
                SUM(opt.Amount),
                0
            ) AS PaidAmount
        FROM order_payment_transaction opt

        INNER JOIN payments p
            ON opt.PaymentID = p.PaymentID

        WHERE opt.OrderID = :orderId
    ";

    $paidStmt = $db->prepare($paidSql);

    $paidStmt->execute([
        ':orderId' => $orderId
    ]);

    $paid = $paidStmt->fetch(PDO::FETCH_ASSOC);

    $alreadyPaid = round(
        (float) ($paid['PaidAmount'] ?? 0),
        2
    );

    /*
     * =========================================================
     * CALCULATE OUTSTANDING BALANCE
     * =========================================================
     */

    $outstanding = round(
        $totalAmount - $alreadyPaid,
        2
    );

    /*
     * =========================================================
     * PREVENT OVERPAID ORDER
     * =========================================================
     */

    if ($outstanding <= 0) {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'This order is already fully paid.',
            'data' => [
                'totalAmount' => $totalAmount,
                'paidAmount' => $alreadyPaid,
                'outstandingAmount' => 0,
                'paymentStatus' => 'PAID'
            ]
        ]);

        exit;
    }

    /*
     * =========================================================
     * PREVENT PAYMENT FROM EXCEEDING BALANCE
     * =========================================================
     */

    if ($paymentAmount > $outstanding) {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Payment exceeds the outstanding balance.',
            'data' => [
                'totalAmount' => $totalAmount,
                'paidAmount' => $alreadyPaid,
                'outstandingAmount' => $outstanding,
                'paymentStatus' =>
                    $alreadyPaid > 0
                        ? 'PARTIALLY_PAID'
                        : 'UNPAID'
            ]
        ]);

        exit;
    }

    /*
     * =========================================================
     * CREATE PAYMENT
     * =========================================================
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
     * =========================================================
     * LINK PAYMENT TO ORDER
     * =========================================================
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

    $transactionStmt = $db->prepare(
        $transactionSql
    );

    $transactionStmt->execute([
        ':orderId' => $orderId,
        ':paymentId' => $paymentId,
        ':amount' => $paymentAmount
    ]);

    /*
     * =========================================================
     * CALCULATE NEW PAYMENT TOTAL
     * =========================================================
     */

    $newPaidAmount = round(
        $alreadyPaid + $paymentAmount,
        2
    );

    $newOutstanding = round(
        $totalAmount - $newPaidAmount,
        2
    );

    /*
     * =========================================================
     * DETERMINE NEW PAYMENT STATUS
     * =========================================================
     */

    if ($newOutstanding <= 0.01) {

        $newOutstanding = 0;

        $paymentStatus = 'PAID';

    } else {

        $paymentStatus = 'PARTIALLY_PAID';
    }

    /*
     * =========================================================
     * UPDATE ORDER PAYMENT STATUS
     * =========================================================
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

    /*
     * =========================================================
     * COMMIT
     * =========================================================
     */

    $db->commit();

    /*
     * =========================================================
     * SUCCESS RESPONSE
     * =========================================================
     */

    echo json_encode([
        'success' => true,
        'message' => 'Payment recorded successfully.',
        'data' => [
            'paymentId' => $paymentId,
            'orderId' => $orderId,

            'totalAmount' => $totalAmount,

            'paidAmount' => $newPaidAmount,

            'outstandingAmount' => $newOutstanding,

            'paymentStatus' => $paymentStatus,

            'receivedByAccId' => $accId,

            'receivedByType' => $account['AccType']
        ]
    ]);

} catch (PDOException $e) {

    if (
        $db !== null &&
        $db->inTransaction()
    ) {
        $db->rollBack();
    }

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error.'
    ]);

} catch (Throwable $e) {

    if (
        $db !== null &&
        $db->inTransaction()
    ) {
        $db->rollBack();
    }

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Unable to process payment.'
    ]);
}
?>


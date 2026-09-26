<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * Accept JSON request.
     */
    $rawInput = file_get_contents('php://input');

    $input = json_decode(
        $rawInput,
        true
    );

    if (!is_array($input)) {
        $input = [];
    }

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $orderId = isset($input['orderId'])
        ? (int) $input['orderId']
        : 0;

    $deliveryId = isset($input['deliveryId'])
        ? (int) $input['deliveryId']
        : 0;

    $bottles = isset($input['bottles'])
        ? $input['bottles']
        : [];

    /*
     * Basic validation.
     */
    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Invalid account, order, or delivery.'
        ]);

        exit;
    }

    if (!is_array($bottles)) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Invalid bottle list.'
        ]);

        exit;
    }

    if (count($bottles) === 0) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Please scan at least one bottle.'
        ]);

        exit;
    }

    /*
     * Maximum protection against accidentally huge
     * requests.
     *
     * The actual quantity is still checked against
     * delivered bottles below.
     */
    if (count($bottles) > 500) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Too many bottles submitted.'
        ]);

        exit;
    }

    /*
     * Validate and normalize bottle input.
     *
     * Expected:
     *
     * {
     *   "bottleNumber": "...",
     *   "latitude": 12.345,
     *   "longitude": 123.456,
     *   "accuracy": 5.2
     * }
     */
    $normalizedBottles = [];

    foreach ($bottles as $index => $bottle) {

        if (!is_array($bottle)) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid bottle data at position ' .
                    ($index + 1) . '.'
            ]);

            exit;
        }

        $bottleNumber = isset($bottle['bottleNumber'])
            ? trim((string) $bottle['bottleNumber'])
            : '';

        if ($bottleNumber === '') {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Bottle number is required at position ' .
                    ($index + 1) . '.'
            ]);

            exit;
        }

        /*
         * GPS values are required for a confirmed pickup.
         */
        if (
            !isset($bottle['latitude']) ||
            !isset($bottle['longitude']) ||
            !isset($bottle['accuracy'])
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'GPS location is required for bottle ' .
                    $bottleNumber . '.'
            ]);

            exit;
        }

        if (
            !is_numeric($bottle['latitude']) ||
            !is_numeric($bottle['longitude']) ||
            !is_numeric($bottle['accuracy'])
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid GPS data for bottle ' .
                    $bottleNumber . '.'
            ]);

            exit;
        }

        $latitude = (float) $bottle['latitude'];
        $longitude = (float) $bottle['longitude'];
        $accuracy = (float) $bottle['accuracy'];

        /*
         * Validate coordinate ranges.
         */
        if (
            $latitude < -90 ||
            $latitude > 90
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid latitude for bottle ' .
                    $bottleNumber . '.'
            ]);

            exit;
        }

        if (
            $longitude < -180 ||
            $longitude > 180
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid longitude for bottle ' .
                    $bottleNumber . '.'
            ]);

            exit;
        }

        if ($accuracy < 0) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid GPS accuracy for bottle ' .
                    $bottleNumber . '.'
            ]);

            exit;
        }

        /*
         * Prevent duplicate bottle numbers within the
         * same submission.
         */
        $duplicateKey = strtoupper($bottleNumber);

        if (isset($normalizedBottles[$duplicateKey])) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Bottle ' .
                    $bottleNumber .
                    ' was scanned more than once.'
            ]);

            exit;
        }

        $normalizedBottles[$duplicateKey] = [
            'bottleNumber' => $bottleNumber,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'accuracy' => $accuracy
        ];
    }

    /*
     * Convert associative array back to indexed array.
     */
    $normalizedBottles = array_values(
        $normalizedBottles
    );

    /*
     * Validate rider account.
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

    if ($account['AccType'] !== 'RIDER') {

        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' =>
                'Only riders can complete a bottle pickup.'
        ]);

        exit;
    }

    /*
     * Start transaction before validating and creating
     * pickup records.
     */
    $db->beginTransaction();

    /*
     * Lock the delivery/order relationship.
     */
    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,
            o.CustomerID,
            o.Quantity,
            o.UnitPrice,
            o.PaymentStatus
        FROM delivery d
        INNER JOIN orders o
            ON d.OrderID = o.OrderID
        WHERE d.DeliveryID = :deliveryId
          AND d.OrderID = :orderId
          AND d.AccID = :accId
        LIMIT 1
        FOR UPDATE
    ";

    $deliveryStmt = $db->prepare($deliverySql);

    $deliveryStmt->execute([
        ':deliveryId' => $deliveryId,
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
                'This delivery is not assigned to this rider.'
        ]);

        exit;
    }

    /*
     * Pickup is only allowed after the delivery has
     * been completed.
     */
    if ($delivery['DeliveryStatus'] !== 'DELIVERED') {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Bottles can only be picked up after the delivery is completed.'
        ]);

        exit;
    }

    /*
     * Count bottles that were actually delivered.
     */
    $deliveredCountSql = "
        SELECT
            COUNT(*) AS DeliveredCount
        FROM order_delivery_transaction odt
        WHERE odt.OrderID = :orderId
          AND odt.DeliveryID = :deliveryId
    ";

    $deliveredCountStmt = $db->prepare(
        $deliveredCountSql
    );

    $deliveredCountStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $deliveredCountRow =
        $deliveredCountStmt->fetch(PDO::FETCH_ASSOC);

    $deliveredCount =
        (int) $deliveredCountRow['DeliveredCount'];

    if ($deliveredCount <= 0) {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'No delivered bottles were found for this order.'
        ]);

        exit;
    }

    /*
     * Prevent picking up more bottles than were delivered.
     */
    if (count($normalizedBottles) > $deliveredCount) {

        $db->rollBack();

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'The number of bottles being picked up exceeds the number delivered.',
            'data' => [
                'deliveredCount' => $deliveredCount,
                'submittedCount' => count($normalizedBottles)
            ]
        ]);

        exit;
    }

    /*
     * Create the pickup header.
     *
     * Nothing has been permanently saved yet because
     * the entire operation is inside the transaction.
     */
    $pickupSql = "
        INSERT INTO pickup
        (
            DeliveryID,
            AccID,
            PickUpDateTime
        )
        VALUES
        (
            :deliveryId,
            :accId,
            NOW()
        )
    ";

    $pickupStmt = $db->prepare($pickupSql);

    $pickupStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $pickUpId = (int) $db->lastInsertId();

    /*
     * Prepared statements for bottle processing.
     */

    $bottleSql = "
        SELECT
            b.BottleID,
            b.BottleNumber
        FROM bottles b
        WHERE b.BottleNumber = :bottleNumber
        LIMIT 1
        FOR UPDATE
    ";

    $bottleStmt = $db->prepare($bottleSql);

    /*
     * Verify the bottle belongs to this delivery.
     */
    $odtSql = "
        SELECT
            odt.ODTID,
            odt.BottleID
        FROM order_delivery_transaction odt
        WHERE odt.OrderID = :orderId
          AND odt.DeliveryID = :deliveryId
          AND odt.BottleID = :bottleId
        LIMIT 1
    ";

    $odtStmt = $db->prepare($odtSql);

    /*
     * Check whether the bottle has already been picked
     * up for this delivery.
     */
    $existingDptSql = "
        SELECT
            dpt.DPTID
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID
        WHERE p.DeliveryID = :deliveryId
          AND dpt.BottleID = :bottleId
        LIMIT 1
    ";

    $existingDptStmt = $db->prepare(
        $existingDptSql
    );

    /*
     * Insert pickup transaction.
     */
    $dptSql = "
        INSERT INTO delivery_pickup_transaction
        (
            PickUpID,
            BottleID
        )
        VALUES
        (
            :pickUpId,
            :bottleId
        )
    ";

    $dptStmt = $db->prepare($dptSql);

    /*
     * Insert immutable pickup scan audit.
     */
    $scanEventSql = "
        INSERT INTO bottle_scan_event
        (
            BottleID,
            AccID,
            EventType,
            OrderID,
            DeliveryID,
            PickUpID,
            ODTID,
            DPTID,
            ScanDateTime,
            Latitude,
            Longitude,
            LocationAccuracy,
            CreatedAt
        )
        VALUES
        (
            :bottleId,
            :accId,
            'PICKUP_SCAN',
            :orderId,
            :deliveryId,
            :pickUpId,
            :odtId,
            :dptId,
            NOW(),
            :latitude,
            :longitude,
            :accuracy,
            NOW()
        )
    ";

    $scanEventStmt = $db->prepare(
        $scanEventSql
    );

    /*
     * Process every temporarily scanned bottle.
     */
    $confirmedBottles = [];

    foreach ($normalizedBottles as $pendingBottle) {

        $bottleNumber =
            $pendingBottle['bottleNumber'];

        /*
         * Find and lock bottle.
         */
        $bottleStmt->execute([
            ':bottleNumber' => $bottleNumber
        ]);

        $bottle =
            $bottleStmt->fetch(PDO::FETCH_ASSOC);

        if (!$bottle) {

            throw new RuntimeException(
                'Bottle ' .
                $bottleNumber .
                ' was not found.'
            );
        }

        $bottleId =
            (int) $bottle['BottleID'];

        /*
         * Confirm that this exact bottle was part of
         * this delivery.
         */
        $odtStmt->execute([
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId,
            ':bottleId' => $bottleId
        ]);

        $odt =
            $odtStmt->fetch(PDO::FETCH_ASSOC);

        if (!$odt) {

            throw new RuntimeException(
                'Bottle ' .
                $bottleNumber .
                ' does not belong to this delivery.'
            );
        }

        $odtId =
            (int) $odt['ODTID'];

        /*
         * Prevent duplicate pickup for this delivery.
         */
        $existingDptStmt->execute([
            ':deliveryId' => $deliveryId,
            ':bottleId' => $bottleId
        ]);

        $existingDpt =
            $existingDptStmt->fetch(PDO::FETCH_ASSOC);

        if ($existingDpt) {

            throw new RuntimeException(
                'Bottle ' .
                $bottleNumber .
                ' has already been picked up for this delivery.'
            );
        }

        /*
         * Create business pickup transaction.
         */
        $dptStmt->execute([
            ':pickUpId' => $pickUpId,
            ':bottleId' => $bottleId
        ]);

        $dptId =
            (int) $db->lastInsertId();

        /*
         * Create immutable scan audit record.
         */
        $scanEventStmt->execute([
            ':bottleId' => $bottleId,
            ':accId' => $accId,
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId,
            ':pickUpId' => $pickUpId,
            ':odtId' => $odtId,
            ':dptId' => $dptId,
            ':latitude' =>
                $pendingBottle['latitude'],
            ':longitude' =>
                $pendingBottle['longitude'],
            ':accuracy' =>
                $pendingBottle['accuracy']
        ]);

        $confirmedBottles[] = [
            'bottleId' => $bottleId,
            'bottleNumber' => $bottleNumber,
            'dptId' => $dptId,
            'odtId' => $odtId
        ];
    }

    /*
     * Safety check.
     */
    if (count($confirmedBottles) === 0) {

        throw new RuntimeException(
            'No bottles were confirmed for pickup.'
        );
    }

    /*
     * Calculate total bottles picked up for this
     * delivery after this transaction.
     */
    $pickedUpCountSql = "
        SELECT
            COUNT(*) AS PickedUpCount
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID
        WHERE p.DeliveryID = :deliveryId
          AND p.AccID = :accId
    ";

    $pickedUpCountStmt = $db->prepare(
        $pickedUpCountSql
    );

    $pickedUpCountStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $pickedUpCountRow =
        $pickedUpCountStmt->fetch(PDO::FETCH_ASSOC);

    $pickedUpCount =
        (int) $pickedUpCountRow['PickedUpCount'];

    /*
     * Calculate payment information while the order
     * remains locked by this transaction.
     */
    $totalAmount = round(
        (float) $delivery['Quantity'] *
        (float) $delivery['UnitPrice'],
        2
    );

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

    $paidRow =
        $paidStmt->fetch(PDO::FETCH_ASSOC);

    $paidAmount = round(
        (float) $paidRow['PaidAmount'],
        2
    );

    $outstandingAmount = round(
        $totalAmount - $paidAmount,
        2
    );

    if ($outstandingAmount <= 0.01) {

        $outstandingAmount = 0;
        $paymentStatus = 'PAID';

    } elseif ($paidAmount > 0) {

        $paymentStatus = 'PARTIALLY_PAID';

    } else {

        $paymentStatus = 'UNPAID';
    }

    /*
     * Commit:
     *
     * pickup
     * DPT
     * bottle_scan_event
     *
     * are all committed together.
     */
    $db->commit();

    /*
     * Return confirmed pickup information.
     */
    echo json_encode([
        'success' => true,
        'message' =>
            'Bottle pickup completed successfully.',
        'data' => [
            'pickUpId' => $pickUpId,
            'orderId' => $orderId,
            'deliveryId' => $deliveryId,
            'scannedCount' => count($confirmedBottles),
            'pickedUpCount' => $pickedUpCount,
            'deliveredCount' => $deliveredCount,
            'remainingCount' =>
                $deliveredCount - $pickedUpCount,

            'paymentStatus' => $paymentStatus,
            'totalAmount' => $totalAmount,
            'paidAmount' => $paidAmount,
            'outstandingAmount' =>
                $outstandingAmount,

            'bottles' => $confirmedBottles
        ]
    ]);

} catch (RuntimeException $e) {

    if (
        $db !== null &&
        $db->inTransaction()
    ) {
        $db->rollBack();
    }

    http_response_code(400);

    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
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
        'message' =>
            'Unable to complete bottle pickup.'
    ]);
}
?>

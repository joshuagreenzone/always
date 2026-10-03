
<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {
    $database = new Database();
    $db = $database->connect();

    /*
     * Read JSON request.
     */
    $rawInput = file_get_contents('php://input');
    $input = json_decode($rawInput, true);

    if (!is_array($input)) {
        $input = [];
    }

    $accId = (int) ($input['accId'] ?? 0);
    $orderId = (int) ($input['orderId'] ?? 0);
    $deliveryId = (int) ($input['deliveryId'] ?? 0);
    $bottles = $input['bottles'] ?? [];

    /*
     * Basic validation.
     */
    if ($accId <= 0 || $orderId <= 0 || $deliveryId <= 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid account, order, or delivery.'
        ]);
        exit;
    }

    if (!is_array($bottles) || count($bottles) === 0) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Please scan at least one bottle.'
        ]);
        exit;
    }

    if (count($bottles) > 500) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Too many bottles submitted.'
        ]);
        exit;
    }

    /*
     * Normalize and validate scanned bottles.
     */
    $normalizedBottles = [];
    $seenBottleNumbers = [];

    foreach ($bottles as $index => $bottle) {
        if (!is_array($bottle)) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Invalid bottle data at position '
                    . ($index + 1) . '.'
            ]);
            exit;
        }

        $bottleNumber = trim(
            (string) ($bottle['bottleNumber'] ?? '')
        );

        if ($bottleNumber === '') {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Bottle number is required at position '
                    . ($index + 1) . '.'
            ]);
            exit;
        }

        if (
            !isset(
                $bottle['latitude'],
                $bottle['longitude'],
                $bottle['accuracy']
            ) ||
            !is_numeric($bottle['latitude']) ||
            !is_numeric($bottle['longitude']) ||
            !is_numeric($bottle['accuracy'])
        ) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Valid GPS location and accuracy are required '
                    . 'for bottle ' . $bottleNumber . '.'
            ]);
            exit;
        }

        $latitude = (float) $bottle['latitude'];
        $longitude = (float) $bottle['longitude'];
        $accuracy = (float) $bottle['accuracy'];

        if (
            $latitude < -90 || $latitude > 90 ||
            $longitude < -180 || $longitude > 180 ||
            $accuracy < 0
        ) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Invalid GPS coordinates or accuracy for bottle '
                    . $bottleNumber . '.'
            ]);
            exit;
        }

        $duplicateKey = strtoupper($bottleNumber);

        if (isset($seenBottleNumbers[$duplicateKey])) {
            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' => 'Bottle ' . $bottleNumber
                    . ' was scanned more than once.'
            ]);
            exit;
        }

        $seenBottleNumbers[$duplicateKey] = true;

        $normalizedBottles[] = [
            'bottleNumber' => $bottleNumber,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'accuracy' => $accuracy
        ];
    }

    /*
     * Verify rider account.
     */
    $accountStmt = $db->prepare("
        SELECT AccID, AccName, AccType
        FROM accounts
        WHERE AccID = :accId
        LIMIT 1
    ");

    $accountStmt->execute([
        ':accId' => $accId
    ]);

    $account = $accountStmt->fetch(PDO::FETCH_ASSOC);

    if (!$account || $account['AccType'] !== 'RIDER') {
        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' => 'Only a valid rider account can complete a bottle pickup.'
        ]);
        exit;
    }

    $db->beginTransaction();

    /*
     * Lock and validate the delivery assigned to this rider.
     */
    $deliveryStmt = $db->prepare("
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,
            o.CustomerID
        FROM delivery d
        INNER JOIN orders o
            ON o.OrderID = d.OrderID
        WHERE d.DeliveryID = :deliveryId
          AND d.OrderID = :orderId
          AND d.AccID = :accId
        LIMIT 1
        FOR UPDATE
    ");

    $deliveryStmt->execute([
        ':deliveryId' => $deliveryId,
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $delivery = $deliveryStmt->fetch(PDO::FETCH_ASSOC);

    if (!$delivery) {
        throw new DomainException(
            'This delivery is not assigned to this rider.'
        );
    }

    /*
     * Pickup is allowed for completed or incomplete deliveries.
     */
    $allowedStatuses = ['DELIVERED', 'INCOMPLETE'];

    if (!in_array($delivery['DeliveryStatus'], $allowedStatuses, true)) {
        throw new DomainException(
            'Bottles can only be picked up after the delivery '
            . 'is completed or marked incomplete.'
        );
    }

    /*
     * Count bottles actually delivered for this delivery.
     */
    $deliveredStmt = $db->prepare("
        SELECT COUNT(*)
        FROM order_delivery_transaction
        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
    ");

    $deliveredStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $deliveredCount = (int) $deliveredStmt->fetchColumn();

    if ($deliveredCount <= 0) {
        throw new DomainException(
            'No delivered bottles were found for this delivery.'
        );
    }

    /*
     * Create pickup header inside the transaction.
     */
    $pickupStmt = $db->prepare("
        INSERT INTO pickup (
            DeliveryID,
            AccID,
            PickUpDateTime
        )
        VALUES (
            :deliveryId,
            :accId,
            NOW()
        )
    ");

    $pickupStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $pickUpId = (int) $db->lastInsertId();

    /*
     * Prepared statements for bottle validation.
     */
    $bottleStmt = $db->prepare("
        SELECT BottleID, BottleNumber
        FROM bottles
        WHERE BottleNumber = :bottleNumber
        LIMIT 1
        FOR UPDATE
    ");

    $odtStmt = $db->prepare("
        SELECT ODTID, BottleID
        FROM order_delivery_transaction
        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
          AND BottleID = :bottleId
        LIMIT 1
    ");

    /*
     * Prevent a bottle from being picked up twice
     * for the same delivery.
     */
    $existingPickupStmt = $db->prepare("
        SELECT dpt.DPTID
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p
            ON p.PickUpID = dpt.PickUpID
        WHERE p.DeliveryID = :deliveryId
          AND dpt.BottleID = :bottleId
        LIMIT 1
    ");

    /*
     * Insert pickup transaction.
     */
    $insertDptStmt = $db->prepare("
        INSERT INTO delivery_pickup_transaction (
            PickUpID,
            BottleID
        )
        VALUES (
            :pickUpId,
            :bottleId
        )
    ");

    /*
     * Record pickup scan and GPS information.
     */
    $scanEventStmt = $db->prepare("
        INSERT INTO bottle_scan_event (
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
        VALUES (
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
    ");

    $confirmedBottles = [];

    /*
     * Validate every scanned bottle before committing.
     */
    foreach ($normalizedBottles as $pendingBottle) {
        $bottleNumber = $pendingBottle['bottleNumber'];

        $bottleStmt->execute([
            ':bottleNumber' => $bottleNumber
        ]);

        $bottle = $bottleStmt->fetch(PDO::FETCH_ASSOC);

        if (!$bottle) {
            throw new DomainException(
                'Bottle ' . $bottleNumber . ' was not found.'
            );
        }

        $bottleId = (int) $bottle['BottleID'];

        /*
         * Confirm that this bottle was delivered on this delivery.
         */
        $odtStmt->execute([
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId,
            ':bottleId' => $bottleId
        ]);

        $odt = $odtStmt->fetch(PDO::FETCH_ASSOC);

        if (!$odt) {
            throw new DomainException(
                'Bottle ' . $bottleNumber
                . ' was not delivered on this delivery and cannot be picked up.'
            );
        }

        $odtId = (int) $odt['ODTID'];

        /*
         * Prevent duplicate pickup.
         */
        $existingPickupStmt->execute([
            ':deliveryId' => $deliveryId,
            ':bottleId' => $bottleId
        ]);

        if ($existingPickupStmt->fetch(PDO::FETCH_ASSOC)) {
            throw new DomainException(
                'Bottle ' . $bottleNumber
                . ' has already been picked up for this delivery.'
            );
        }

        /*
         * Save pickup transaction.
         */
        $insertDptStmt->execute([
            ':pickUpId' => $pickUpId,
            ':bottleId' => $bottleId
        ]);

        $dptId = (int) $db->lastInsertId();

        /*
         * Save scan audit record.
         */
        $scanEventStmt->execute([
            ':bottleId' => $bottleId,
            ':accId' => $accId,
            ':orderId' => $orderId,
            ':deliveryId' => $deliveryId,
            ':pickUpId' => $pickUpId,
            ':odtId' => $odtId,
            ':dptId' => $dptId,
            ':latitude' => $pendingBottle['latitude'],
            ':longitude' => $pendingBottle['longitude'],
            ':accuracy' => $pendingBottle['accuracy']
        ]);

        $confirmedBottles[] = [
            'bottleId' => $bottleId,
            'bottleNumber' => $bottleNumber,
            'dptId' => $dptId,
            'odtId' => $odtId
        ];
    }

    if (count($confirmedBottles) === 0) {
        throw new DomainException(
            'No bottles were confirmed for pickup.'
        );
    }

    /*
     * Count all bottles picked up for this delivery.
     */
    $pickedUpStmt = $db->prepare("
        SELECT COUNT(*)
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p
            ON p.PickUpID = dpt.PickUpID
        WHERE p.DeliveryID = :deliveryId
    ");

    $pickedUpStmt->execute([
        ':deliveryId' => $deliveryId
    ]);

    $pickedUpCount = (int) $pickedUpStmt->fetchColumn();

    /*
     * Calculate the value of bottles actually delivered.
     *
     * This deliberately excludes order items that were
     * not delivered. Each ODT record represents one bottle.
     */
    $deliveredValueStmt = $db->prepare("
        SELECT COALESCE(SUM(oi.UnitPrice), 0)
        FROM order_delivery_transaction odt
        INNER JOIN order_items oi
            ON oi.OrderItemID = odt.OrderItemID
        WHERE odt.OrderID = :orderId
          AND odt.DeliveryID = :deliveryId
    ");

    $deliveredValueStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $deliveredAmount = round(
        (float) $deliveredValueStmt->fetchColumn(),
        2
    );

    /*
     * Calculate payments already allocated to this order.
     *
     * Pickup does not create or modify payment records.
     */
    $paidStmt = $db->prepare("
        SELECT COALESCE(SUM(Amount), 0)
        FROM order_payment_transaction
        WHERE OrderID = :orderId
    ");

    $paidStmt->execute([
        ':orderId' => $orderId
    ]);

    $paidAmount = round(
        (float) $paidStmt->fetchColumn(),
        2
    );

    /*
     * Balance is based on delivered value, not the full
     * original order value.
     */
    $outstandingAmount = round(
        max(0, $deliveredAmount - $paidAmount),
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
     * Commit pickup records and scan events together.
     */
    $db->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Bottle pickup completed successfully.',
        'data' => [
            'pickUpId' => $pickUpId,
            'orderId' => $orderId,
            'deliveryId' => $deliveryId,
            'scannedCount' => count($confirmedBottles),
            'pickedUpCount' => $pickedUpCount,
            'deliveredCount' => $deliveredCount,
            'remainingCount' => max(
                0,
                $deliveredCount - $pickedUpCount
            ),
            'paymentStatus' => $paymentStatus,
            'totalAmount' => $deliveredAmount,
            'deliveredAmount' => $deliveredAmount,
            'paidAmount' => $paidAmount,
            'outstandingAmount' => $outstandingAmount,
            'bottles' => $confirmedBottles
        ]
    ]);

} catch (DomainException $e) {
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }

    http_response_code(400);

    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);

} catch (PDOException $e) {
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }

    error_log(
        'Syawla pickup database error: ' . $e->getMessage()
    );

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Database error while completing pickup.'
    ]);

} catch (Throwable $e) {
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }

    error_log(
        'Syawla pickup error: ' . $e->getMessage()
    );

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Unable to complete bottle pickup.'
    ]);
}
?>
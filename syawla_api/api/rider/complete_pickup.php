<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    $input = json_decode(
        file_get_contents('php://input'),
        true
    );

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $orderId = isset($input['orderId'])
        ? (int) $input['orderId']
        : 0;

    $deliveryId = isset($input['deliveryId'])
        ? (int) $input['deliveryId']
        : 0;

    $pickUpId = isset($input['pickUpId'])
        ? (int) $input['pickUpId']
        : 0;

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0 ||
        $pickUpId <= 0
    ) {
        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid pickup information.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 1. Verify pickup belongs to this rider and delivery.
     * ---------------------------------------------------------
     */

    $pickupSql = "
        SELECT
            p.PickUpID,
            p.DeliveryID,
            p.AccID,
            d.OrderID,
            d.DeliveryStatus,
            o.Quantity

        FROM pickup p

        INNER JOIN delivery d
            ON p.DeliveryID = d.DeliveryID

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        WHERE p.PickUpID = :pickUpId
          AND p.DeliveryID = :deliveryId
          AND p.AccID = :accId
          AND d.OrderID = :orderId
          AND d.DeliveryStatus = 'DELIVERED'

        LIMIT 1
    ";

    $pickupStmt = $db->prepare($pickupSql);

    $pickupStmt->execute([
        ':pickUpId' => $pickUpId,
        ':deliveryId' => $deliveryId,
        ':accId' => $accId,
        ':orderId' => $orderId
    ]);

    $pickup = $pickupStmt->fetch();

    if (!$pickup) {

        http_response_code(404);

        echo json_encode([
            'success' => false,
            'message' =>
                'Pickup session not found.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 2. Count bottles actually delivered.
     * ---------------------------------------------------------
     */

    $deliveredSql = "
        SELECT
            COUNT(DISTINCT BottleID) AS DeliveredCount

        FROM order_delivery_transaction

        WHERE OrderID = :orderId
          AND DeliveryID = :deliveryId
    ";

    $deliveredStmt = $db->prepare(
        $deliveredSql
    );

    $deliveredStmt->execute([
        ':orderId' => $orderId,
        ':deliveryId' => $deliveryId
    ]);

    $delivered = $deliveredStmt->fetch();

    $deliveredCount =
        (int) $delivered['DeliveredCount'];

    if ($deliveredCount <= 0) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'No delivered bottles were found for this delivery.'
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 3. Count ALL bottles picked up for this delivery.
     *
     *    IMPORTANT:
     *    We count across the delivery, not only this PickUpID.
     *
     *    This allows:
     *
     *    Pickup #1 = 3
     *    Pickup #2 = 2
     *
     *    Total = 5
     * ---------------------------------------------------------
     */

    $pickedUpSql = "
        SELECT
            COUNT(DISTINCT dpt.BottleID) AS PickedUpCount

        FROM pickup p

        INNER JOIN delivery_pickup_transaction dpt
            ON p.PickUpID = dpt.PickUpID

        WHERE p.DeliveryID = :deliveryId
          AND p.AccID = :accId
    ";

    $pickedUpStmt = $db->prepare(
        $pickedUpSql
    );

    $pickedUpStmt->execute([
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $pickedUp = $pickedUpStmt->fetch();

    $pickedUpCount =
        (int) $pickedUp['PickedUpCount'];

    /*
     * ---------------------------------------------------------
     * 4. Validate pickup quantity.
     * ---------------------------------------------------------
     */

    if ($pickedUpCount <= 0) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'At least one bottle must be picked up before completing this pickup.'
        ]);

        exit;
    }

    if ($pickedUpCount > $deliveredCount) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'Picked up bottle count exceeds delivered bottle count.',
            'data' => [
                'delivered' => $deliveredCount,
                'pickedUp' => $pickedUpCount
            ]
        ]);

        exit;
    }

    /*
     * ---------------------------------------------------------
     * 5. Calculate remaining bottles.
     * ---------------------------------------------------------
     */

    $remainingCount =
        $deliveredCount - $pickedUpCount;

    /*
     * ---------------------------------------------------------
     * 6. Update pickup timestamp.
     *
     *    Partial pickup is valid.
     *
     *    We do NOT change DeliveryStatus here.
     *
     *    The delivery remains DELIVERED while bottles are
     *    still outstanding for pickup.
     * ---------------------------------------------------------
     */

    $db->beginTransaction();

    $updateSql = "
        UPDATE pickup

        SET PickUpDateTime = NOW()

        WHERE PickUpID = :pickUpId
          AND DeliveryID = :deliveryId
          AND AccID = :accId
    ";

    $updateStmt = $db->prepare($updateSql);

    $updateStmt->execute([
        ':pickUpId' => $pickUpId,
        ':deliveryId' => $deliveryId,
        ':accId' => $accId
    ]);

    $db->commit();

    /*
     * ---------------------------------------------------------
     * 7. Return partial/full pickup status.
     * ---------------------------------------------------------
     */

    if ($remainingCount > 0) {

        echo json_encode([
            'success' => true,
            'message' =>
                'Partial pickup completed successfully. '
                . $remainingCount
                . ' bottle'
                . ($remainingCount === 1 ? '' : 's')
                . ' remain to be picked up.',
            'data' => [
                'pickUpId' => $pickUpId,
                'deliveryId' => $deliveryId,
                'orderId' => $orderId,
                'deliveredCount' => $deliveredCount,
                'pickedUpCount' => $pickedUpCount,
                'remainingCount' => $remainingCount,
                'pickupCompleted' => false
            ]
        ]);

        exit;
    }

    /*
     * All delivered bottles have now been picked up.
     */

    echo json_encode([
        'success' => true,
        'message' =>
            'Pickup completed successfully. All delivered bottles have been picked up.',
        'data' => [
            'pickUpId' => $pickUpId,
            'deliveryId' => $deliveryId,
            'orderId' => $orderId,
            'deliveredCount' => $deliveredCount,
            'pickedUpCount' => $pickedUpCount,
            'remainingCount' => 0,
            'pickupCompleted' => true
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
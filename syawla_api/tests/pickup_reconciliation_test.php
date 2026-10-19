<?php

// Development database only. Every fixture and scan is rolled back.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_cycle.php';

function pickupRemaining(PDO $db, int $riderId, int $deliveryId): int
{
    // Exercise the same query used by the rider's pickup queue.
    $source = file_get_contents(__DIR__ . '/../api/rider/get_pickup_orders.php');
    if (!preg_match('/\$sql = "(.*?)";/s', $source, $match)) {
        throw new RuntimeException('Pickup queue query was not found.');
    }
    $stmt = $db->prepare($match[1]);
    $stmt->execute([':accId' => $riderId]);
    $remaining = 0;
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        if ((int) $row['DeliveryID'] === $deliveryId) {
            $remaining += (int) $row['RemainingBottleCount'];
        }
    }
    return $remaining; // Fully resolved deliveries disappear from the queue.
}

$db = (new Database())->connect();
$delivery = $db->query("SELECT d.DeliveryID, d.OrderID, d.AccID
    FROM delivery d INNER JOIN accounts a ON a.AccID = d.AccID
    WHERE EXISTS (SELECT 1 FROM account_roles ar WHERE ar.AccID = a.AccID AND ar.Role = 'RIDER') AND d.DeliveryStatus IN ('DELIVERED', 'INCOMPLETE')
    LIMIT 1")->fetch(PDO::FETCH_ASSOC);
$typeId = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
if (!$delivery || !$typeId) {
    throw new RuntimeException('A delivered rider order and bottle type are required.');
}

$db->beginTransaction();
try {
    $riderId = (int) $delivery['AccID'];
    $deliveryId = (int) $delivery['DeliveryID'];
    $baseline = pickupRemaining($db, $riderId, $deliveryId);
    $number = 'RECON-' . bin2hex(random_bytes(6));
    $stmt = $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)');
    $stmt->execute([$number, $typeId]);
    $bottleId = (int) $db->lastInsertId();
    $stmt = $db->prepare('INSERT INTO order_delivery_transaction (OrderID, DeliveryID, BottleID) VALUES (?, ?, ?)');
    $stmt->execute([(int) $delivery['OrderID'], $deliveryId, $bottleId]);
    $odtId = (int) $db->lastInsertId();
    $stmt = $db->prepare("INSERT INTO bottle_scan_event
        (BottleID, AccID, EventType, ODTID, OrderID, DeliveryID)
        VALUES (?, ?, 'DELIVERY_SCAN', ?, ?, ?)");
    $stmt->execute([$bottleId, $riderId, $odtId, (int) $delivery['OrderID'], $deliveryId]);
    if (pickupRemaining($db, $riderId, $deliveryId) !== $baseline + 1) {
        throw new RuntimeException('A delivered bottle did not enter the pickup queue.');
    }

    saveVehicleBatch($db, $riderId, 'RETURN', [$number], [strtolower($number) => [
        'jumpReason' => 'Picked up but pickup scan was missed'
    ]]);
    if (pickupRemaining($db, $riderId, $deliveryId) !== $baseline) {
        throw new RuntimeException('The reasoned return did not resolve the pending pickup.');
    }
    $stmt = $db->prepare("SELECT ODTID, OrderID, DeliveryID, IsCycleJump, JumpReason
        FROM bottle_scan_event WHERE BottleID = ? AND EventType = 'UNLOAD_SCAN'
        ORDER BY ScanEventID DESC LIMIT 1");
    $stmt->execute([$bottleId]);
    $event = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$event || (int) $event['ODTID'] !== $odtId
        || (int) $event['OrderID'] !== (int) $delivery['OrderID']
        || (int) $event['DeliveryID'] !== $deliveryId
        || (int) $event['IsCycleJump'] !== 1
        || $event['JumpReason'] !== 'Picked up but pickup scan was missed') {
        throw new RuntimeException('The return audit event lost its delivery link or reason.');
    }
    $stmt = $db->prepare('SELECT COUNT(*) FROM delivery_pickup_transaction WHERE BottleID = ?');
    $stmt->execute([$bottleId]);
    if ((int) $stmt->fetchColumn() !== 0) {
        throw new RuntimeException('The return invented a pickup transaction.');
    }
    echo 'Pickup reconciliation passed; all fixtures were rolled back.', PHP_EOL;
} finally {
    $db->rollBack();
}

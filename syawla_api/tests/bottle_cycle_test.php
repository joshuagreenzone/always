<?php

// Development database only. All new fixtures and scans are rolled back.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_cycle.php';
function checkCycle(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
function rejectCycle(callable $action, string $type = DomainException::class): void {
    try { $action(); } catch (Throwable $e) {
        checkCycle($e instanceof $type, 'Unexpected failure: ' . $e->getMessage());
        return;
    }
    throw new RuntimeException('Expected the scan to be rejected.');
}
$db = (new Database())->connect();
$db->beginTransaction();
try {
    $rider = (int) $db->query("SELECT AccID FROM accounts WHERE AccType = 'RIDER' LIMIT 1")->fetchColumn();
    $worker = (int) $db->query("SELECT AccID FROM accounts WHERE AccType = 'STATION_WORKER' LIMIT 1")->fetchColumn();
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $pickup = $db->query("SELECT p.PickUpID, d.DeliveryID, d.OrderID FROM pickup p
        INNER JOIN delivery d ON d.DeliveryID = p.DeliveryID WHERE p.AccID = {$rider} LIMIT 1")->fetch(PDO::FETCH_ASSOC);
    checkCycle($rider && $worker && $type && $pickup, 'Existing rider pickup fixtures are required.');
    $token = bin2hex(random_bytes(6));
    $stmt = $db->prepare("INSERT INTO accounts (AccName, AccEmail, AccUsername, AccPassword, AccType)
        VALUES ('Cycle test', ?, ?, 'test-only', 'RIDER')");
    $stmt->execute(["cycle-{$token}@example.invalid", "cycle-{$token}"]);
    $otherRider = (int) $db->lastInsertId();
    $number = 'CYCLE-' . $token;
    $stmt = $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)');
    $stmt->execute([$number, $type]);
    $id = (int) $db->lastInsertId();
    $stmt = $db->prepare('INSERT INTO refill (BottleID) VALUES (?)');
    $stmt->execute([$id]);
    $refill = (int) $db->lastInsertId();
    $activity = $db->prepare('INSERT INTO bottle_scan_event (BottleID, AccID, EventType, RefillID, ODTID, DPTID) VALUES (?, ?, ?, ?, ?, ?)');
    $activity->execute([$id, $worker, 'REFILL_SCAN', $refill, null, null]);
    checkCycle(verifyVehicleBottle($db, $rider, $number, 'LOAD')['cycle']['CycleStatus'] === 'READY',
        'A refill scan without a bottle_cycle row must be loadable.');
    setBottleCycle($db, $id, 'DELIVERED', $rider, $refill);
    checkCycle(verifyVehicleBottle($db, $rider, $number, 'LOAD')['cycle']['CycleStatus'] === 'READY',
        'A stale snapshot must not override the latest refill scan.');
    rejectCycle(fn() => requireLoadedBottle($db, $id, $rider));
    rejectCycle(fn() => verifyVehicleBottle($db, $rider, $number, 'RETURN'));
    rejectCycle(fn() => saveVehicleBatch($db, $worker, 'LOAD', [$number]), UnexpectedValueException::class);
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'LOAD', [$number, strtolower($number)]), InvalidArgumentException::class);
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'LOAD', []), InvalidArgumentException::class);
    // A failed batch must not partially load its valid bottle.
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'LOAD', [$number, 'NOT-REGISTERED-' . $token]), OutOfBoundsException::class);
    checkCycle(getBottleCycle($db, $id)['CycleStatus'] === 'READY', 'Invalid batch changed inventory.');
    $eventCount = $db->prepare('SELECT COUNT(*) FROM bottle_scan_event WHERE BottleID = ?');
    $eventCount->execute([$id]);
    checkCycle((int) $eventCount->fetchColumn() === 1, 'Invalid batch recorded a scan event.');
    $loaded = saveVehicleBatch($db, $rider, 'LOAD', [$number]);
    checkCycle($loaded['count'] === 1, 'Loaded count is incorrect.');
    $events = $db->prepare("SELECT * FROM bottle_scan_event WHERE BottleID = ? AND EventType IN ('LOAD_SCAN', 'UNLOAD_SCAN') ORDER BY ScanEventID");
    $events->execute([$id]);
    $loadEvent = $events->fetch(PDO::FETCH_ASSOC);
    checkCycle($loadEvent['EventType'] === 'LOAD_SCAN' && (int) $loadEvent['AccID'] === $rider
        && (int) $loadEvent['RefillID'] === $refill && !empty($loadEvent['ScanDateTime']), 'Loading event was not recorded correctly.');
    requireLoadedBottle($db, $id, $rider);
    $olderEvent = $db->prepare("INSERT INTO bottle_scan_event (BottleID, AccID, EventType, RefillID, ScanDateTime)
        VALUES (?, ?, 'REFILL_SCAN', ?, CURRENT_TIMESTAMP - INTERVAL 1 DAY)");
    $olderEvent->execute([$id, $worker, $refill]);
    requireLoadedBottle($db, $id, $rider);
    rejectCycle(fn() => requireLoadedBottle($db, $id, $otherRider));
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'LOAD', [$number]));
    rejectCycle(fn() => requireBottleAtStationForRefill($db, $id));

    $stmt = $db->prepare('INSERT INTO order_delivery_transaction (OrderID, DeliveryID, BottleID) VALUES (?, ?, ?)');
    $stmt->execute([$pickup['OrderID'], $pickup['DeliveryID'], $id]);
    $odt = (int) $db->lastInsertId();
    $activity->execute([$id, $rider, 'DELIVERY_SCAN', null, $odt, null]);
    // Leave the snapshot loaded: a real delivery event must override it.
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'RETURN', [$number]));
    requireBottlePickupCycle($db, $id, $rider, $odt);
    rejectCycle(fn() => requireBottlePickupCycle($db, $id, $rider, $odt + 1));
    $stmt = $db->prepare('INSERT INTO delivery_pickup_transaction (PickUpID, BottleID) VALUES (?, ?)');
    $stmt->execute([$pickup['PickUpID'], $id]);
    $dpt = (int) $db->lastInsertId();
    $activity->execute([$id, $rider, 'PICKUP_SCAN', null, $odt, $dpt]);
    // The pickup scan supplies the current rider and pickup reference itself.
    $db->prepare('DELETE FROM bottle_cycle WHERE BottleID = ?')->execute([$id]);
    checkCycle(verifyVehicleBottle($db, $rider, $number, 'RETURN')['cycle']['DPTID'] == $dpt,
        'A pickup event without a cycle snapshot must allow station return.');
    // Older pickup events may identify the pickup header rather than its detail.
    $db->prepare("UPDATE bottle_scan_event SET DPTID = NULL, PickUpID = ? WHERE BottleID = ? AND EventType = 'PICKUP_SCAN'")
        ->execute([$pickup['PickUpID'], $id]);
    checkCycle(verifyVehicleBottle($db, $rider, $number, 'RETURN')['cycle']['DPTID'] == $dpt,
        'Pickup header must resolve the matching bottle pickup detail.');
    rejectCycle(fn() => requireBottleAtStationForRefill($db, $id));
    rejectCycle(fn() => saveVehicleBatch($db, $otherRider, 'RETURN', [$number]));
    updateBottleCondition($db, $rider, $number, 'HEALTHY', 'DAMAGED', 'Crack found during collection');
    rejectCycle(fn() => requireLoadedBottle($db, $id, $rider));
    $returned = saveVehicleBatch($db, $rider, 'RETURN', [$number]);
    checkCycle($returned['count'] === 1 && $returned['status'] === 'RETURNED', 'Arrival count/state is incorrect.');
    checkCycle(getBottleCondition($db, $number)['condition'] === 'DAMAGED', 'Damaged return must keep its condition.');
    $events->execute([$id]);
    $scanEvents = $events->fetchAll(PDO::FETCH_ASSOC);
    checkCycle(count($scanEvents) === 2, 'Expected one loading and one unloading event.');
    $unloadEvent = $scanEvents[1];
    checkCycle($unloadEvent['EventType'] === 'UNLOAD_SCAN' && (int) $unloadEvent['AccID'] === $rider
        && (int) $unloadEvent['DPTID'] === $dpt && (int) $unloadEvent['ODTID'] === $odt
        && (int) $unloadEvent['PickUpID'] === (int) $pickup['PickUpID']
        && (int) $unloadEvent['DeliveryID'] === (int) $pickup['DeliveryID']
        && (int) $unloadEvent['OrderID'] === (int) $pickup['OrderID']
        && !empty($unloadEvent['ScanDateTime']), 'Unloading event was not linked to its pickup.');
    rejectCycle(fn() => saveVehicleBatch($db, $rider, 'RETURN', [$number]));
    rejectCycle(fn() => verifyVehicleBottle($db, $rider, $number, 'LOAD'));
    updateBottleCondition($db, $worker, $number, 'DAMAGED', 'HEALTHY', 'Repaired at station');
    checkCycle(requireBottleAtStationForRefill($db, $id), 'Returned bottle should be eligible for station refill.');
    rejectCycle(fn() => verifyVehicleBottle($db, $rider, $number, 'LOAD'));
    $stmt = $db->prepare('INSERT INTO refill (BottleID) VALUES (?)');
    $stmt->execute([$id]);
    $freshRefill = (int) $db->lastInsertId();
    $activity->execute([$id, $worker, 'REFILL_SCAN', $freshRefill, null, null]);
    setBottleCycle($db, $id, 'READY', null, $freshRefill);
    rejectCycle(fn() => requireLoadedBottle($db, $id, $rider));
    saveVehicleBatch($db, $rider, 'LOAD', [$number]);
    requireLoadedBottle($db, $id, $rider);
    $stmt = $db->prepare('SELECT SUM(BottleCount) FROM vehicle_scan_batch WHERE BatchID = ?');
    $stmt->execute([$returned['batchId']]);
    checkCycle((int) $stmt->fetchColumn() === 1, 'Station-arrival count was not recorded.');
    $events->execute([$id]);
    checkCycle(array_column($events->fetchAll(PDO::FETCH_ASSOC), 'EventType') === ['LOAD_SCAN', 'UNLOAD_SCAN', 'LOAD_SCAN'],
        'Repeated trips or rejected scans produced incorrect events.');
    $db->rollBack();
    checkCycle(getBottleCondition($db, $number) === null, 'Cycle fixtures were not rolled back.');
    echo "Vehicle cycle checks passed; fixtures and all scans rolled back.\n";
} finally { if ($db->inTransaction()) $db->rollBack(); }

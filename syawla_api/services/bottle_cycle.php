<?php

require_once __DIR__ . '/bottle_condition.php';

const BOTTLE_CYCLE_LABELS = [
    'READY' => 'Ready for Loading', 'LOADED' => 'Loaded for Delivery',
    'DELIVERED' => 'Delivered to Customer', 'COLLECTED' => 'Collected from Customer',
    'RETURNED' => 'Returned to Station'
];

function requireCycleRider(PDO $db, int $accId): void
{
    $stmt = $db->prepare('SELECT AccType FROM accounts WHERE AccID = ?');
    $stmt->execute([$accId]);
    if ($stmt->fetchColumn() !== 'RIDER') {
        throw new UnexpectedValueException('Only riders can load or return bottles.');
    }
}

// Scan history is authoritative; bottle_cycle is only a write-through snapshot.
function bottleCurrentCycleSql(): string
{
    return "SELECT b.BottleID,
        CASE WHEN pm.MovementID IS NOT NULL AND (s.ScanDateTime IS NULL OR pm.MovementDateTime >= s.ScanDateTime)
            THEN IF(pm.MovementType = 'RETURN', 'RETURNED', 'DELIVERED')
            WHEN s.EventType = 'REFILL_SCAN' THEN 'READY'
            WHEN s.EventType = 'LOAD_SCAN' THEN 'LOADED'
            WHEN s.EventType = 'DELIVERY_SCAN' THEN 'DELIVERED'
            WHEN s.EventType = 'PICKUP_SCAN' THEN 'COLLECTED'
            WHEN s.EventType = 'UNLOAD_SCAN' THEN 'RETURNED'
            WHEN r.RefillID IS NOT NULL THEN 'READY' END AS CycleStatus,
        CASE WHEN pm.MovementID IS NOT NULL AND (s.ScanDateTime IS NULL OR pm.MovementDateTime >= s.ScanDateTime)
            THEN NULL WHEN s.EventType <> 'REFILL_SCAN' THEN s.AccID END AS AccID,
        COALESCE(s.RefillID, r.RefillID) AS RefillID, s.ODTID,
        COALESCE(s.DPTID, CASE WHEN s.EventType = 'PICKUP_SCAN' THEN
            (SELECT dpt.DPTID FROM delivery_pickup_transaction dpt
             WHERE dpt.PickUpID = s.PickUpID AND dpt.BottleID = b.BottleID LIMIT 1) END) AS DPTID,
        GREATEST(COALESCE(s.ScanDateTime, r.RefillDateTime, b.BottleRegDateTime),
            COALESCE(pm.MovementDateTime, '1000-01-01')) AS UpdatedAt
        FROM bottles b
        LEFT JOIN bottle_scan_event s ON s.ScanEventID =
            (SELECT e.ScanEventID FROM bottle_scan_event e WHERE e.BottleID = b.BottleID
             ORDER BY e.ScanDateTime DESC, e.ScanEventID DESC LIMIT 1)
        LEFT JOIN refill r ON r.RefillID = (SELECT MAX(rr.RefillID) FROM refill rr WHERE rr.BottleID = b.BottleID)
        LEFT JOIN premise_bottle_movement pm ON pm.MovementID =
            (SELECT MAX(m.MovementID) FROM premise_bottle_movement m WHERE m.BottleID = b.BottleID)";
}

function getBottleCycle(PDO $db, int $id): ?array
{
    // Mutating callers already hold the bottle row lock while reading this history.
    $stmt = $db->prepare('SELECT * FROM (' . bottleCurrentCycleSql() . ') c WHERE BottleID = ?');
    $stmt->execute([$id]);
    $cycle = $stmt->fetch(PDO::FETCH_ASSOC);
    return $cycle && $cycle['CycleStatus'] !== null ? $cycle : null;
}

// Every caller holds the bottles row lock and owns the transaction.
function setBottleCycle(PDO $db, int $id, string $status, ?int $accId, ?int $refillId = null, ?int $odtId = null, ?int $dptId = null): void
{
    if (!$db->inTransaction()) {
        throw new LogicException('Bottle cycle changes require a transaction.');
    }
    $stmt = $db->prepare('INSERT INTO bottle_cycle (BottleID, CycleStatus, AccID, RefillID, ODTID, DPTID, UpdatedAt)
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP(6))
        ON DUPLICATE KEY UPDATE CycleStatus = VALUES(CycleStatus), AccID = VALUES(AccID),
        RefillID = VALUES(RefillID), ODTID = VALUES(ODTID), DPTID = VALUES(DPTID), UpdatedAt = VALUES(UpdatedAt)');
    $stmt->execute([$id, $status, $accId, $refillId, $odtId, $dptId]);
}

function requireLoadedBottle(PDO $db, int $id, int $accId): array
{
    requireBottleReadyForDelivery($db, $id);
    $cycle = getBottleCycle($db, $id);
    if (!$cycle || $cycle['CycleStatus'] !== 'LOADED' || (int) $cycle['AccID'] !== $accId) {
        throw new BottleConditionConflict('Scan this bottle in Load for Delivery first. It must be loaded by the rider delivering it.');
    }
    return $cycle;
}

function requireBottlePickupCycle(PDO $db, int $id, int $accId, int $odtId): void
{
    $cycle = getBottleCycle($db, $id);
    if (!$cycle || $cycle['CycleStatus'] !== 'DELIVERED' || (int) $cycle['AccID'] !== $accId || (int) $cycle['ODTID'] !== $odtId) {
        throw new BottleConditionConflict('This bottle is no longer awaiting pickup for this delivery. Check its current bottle cycle.');
    }
}

function requireBottleAtStationForRefill(PDO $db, int $id): bool
{
    $cycle = getBottleCycle($db, $id);
    if (!$cycle) return false;
    $status = $cycle['CycleStatus'];
    if (in_array($status, ['DELIVERED', 'COLLECTED'], true) ||
        ($status === 'LOADED' && !bottleNeedsRecoveryRefill($db, $id))) {
        throw new BottleConditionConflict('This bottle has not returned to the station. Collected bottles must be scanned in Return to Station before refill.');
    }
    return $status === 'RETURNED';
}

function verifyVehicleBottle(PDO $db, int $accId, string $number, string $action): array
{
    requireCycleRider($db, $accId);
    if (!in_array($action, ['LOAD', 'RETURN', 'DELIVERY'], true)) {
        throw new InvalidArgumentException('Invalid scanning process.');
    }
    $bottle = getBottleCondition($db, $number, $db->inTransaction());
    if (!$bottle) throw new OutOfBoundsException('Bottle not found.');
    $id = $bottle['bottleId'];
    if ($action === 'DELIVERY') {
        requireLoadedBottle($db, $id, $accId);
        return $bottle;
    }
    requireHealthyBottle($db, $id, $action === 'RETURN');
    $cycle = getBottleCycle($db, $id);
    if ($action === 'LOAD') {
        requireBottleReadyForDelivery($db, $id);
        if (!$cycle || $cycle['CycleStatus'] !== 'READY' || !$cycle['RefillID']) {
            if ($cycle && $cycle['CycleStatus'] === 'LOADED') {
                throw new BottleConditionConflict('This bottle is already Loaded for Delivery. It cannot be loaded twice.');
            }
            $label = $cycle ? BOTTLE_CYCLE_LABELS[$cycle['CycleStatus']] : 'Not Refilled';
            throw new BottleConditionConflict('Bottle is currently ' . $label . '. Its latest activity must be a refill before loading.');
        }
    } else {
        if ($cycle && $cycle['CycleStatus'] === 'RETURNED') {
            throw new BottleConditionConflict("Bottle {$number} is already back at the station. It cannot be returned twice.");
        }
        if (!$cycle || $cycle['CycleStatus'] !== 'COLLECTED') {
            throw new BottleConditionConflict("Pick up bottle {$number} from the customer first, then scan it here when you unload it at the station.");
        }
        if ((int) $cycle['AccID'] !== $accId) {
            throw new BottleConditionConflict("Bottle {$number} was picked up by another rider. That rider must confirm its return to the station.");
        }
        if (!$cycle['DPTID']) {
            throw new BottleConditionConflict("Bottle {$number} has no matching pickup record. Ask the station staff to check its pickup history.");
        }
        $stmt = $db->prepare('SELECT 1 FROM delivery_pickup_transaction dpt INNER JOIN pickup p ON p.PickUpID = dpt.PickUpID
            WHERE dpt.DPTID = ? AND dpt.BottleID = ? AND p.AccID = ?');
        $stmt->execute([$cycle['DPTID'], $id, $accId]);
        if (!$stmt->fetchColumn()) throw new BottleConditionConflict("Bottle {$number}'s pickup record does not match this rider. Ask the station staff to check its pickup history.");
    }
    return $bottle + ['cycle' => $cycle];
}

function saveVehicleBatch(PDO $db, int $accId, string $action, array $numbers): array
{
    if (!$db->inTransaction()) throw new LogicException('Vehicle scans require a transaction.');
    requireCycleRider($db, $accId);
    if (!in_array($action, ['LOAD', 'RETURN'], true) || count($numbers) < 1 || count($numbers) > 200) {
        throw new InvalidArgumentException('Choose a valid process and 1 to 200 bottles.');
    }
    $normalized = [];
    foreach ($numbers as $number) {
        if (!is_string($number) || trim($number) === '') throw new InvalidArgumentException('Invalid bottle number.');
        $key = strtolower(trim($number));
        if (isset($normalized[$key])) throw new InvalidArgumentException('A bottle was scanned more than once.');
        $normalized[$key] = trim($number);
    }
    // Consistent lock order for concurrent batches. Validation precedes all writes.
    ksort($normalized);
    $verified = [];
    foreach ($normalized as $number) $verified[] = verifyVehicleBottle($db, $accId, $number, $action);
    $stmt = $db->prepare('INSERT INTO vehicle_scan_batch (AccID, Action, BottleCount) VALUES (?, ?, ?)');
    $stmt->execute([$accId, $action, count($verified)]);
    $batchId = (int) $db->lastInsertId();
    $eventStmt = $db->prepare('INSERT INTO bottle_scan_event
        (BottleID, AccID, EventType, RefillID, ODTID, DPTID, OrderID, DeliveryID, PickUpID, ScanDateTime)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ScannedAt FROM vehicle_scan_batch WHERE BatchID = ?');
    $pickupStmt = $db->prepare('SELECT p.PickUpID, p.DeliveryID, d.OrderID
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p ON p.PickUpID = dpt.PickUpID
        INNER JOIN delivery d ON d.DeliveryID = p.DeliveryID WHERE dpt.DPTID = ?');
    $stmt = $db->prepare('INSERT INTO vehicle_bottle_scan (BatchID, BottleID, RefillID, DPTID) VALUES (?, ?, ?, ?)');
    foreach ($verified as $bottle) {
        $cycle = $bottle['cycle'];
        $stmt->execute([$batchId, $bottle['bottleId'], $cycle['RefillID'], $action === 'RETURN' ? $cycle['DPTID'] : null]);
        $pickup = null;
        if ($action === 'RETURN') {
            $pickupStmt->execute([$cycle['DPTID']]);
            $pickup = $pickupStmt->fetch(PDO::FETCH_ASSOC);
            if (!$pickup) throw new BottleConditionConflict('The confirmed pickup could not be found.');
        }
        $eventStmt->execute([$bottle['bottleId'], $accId, $action === 'LOAD' ? 'LOAD_SCAN' : 'UNLOAD_SCAN',
            $cycle['RefillID'], $action === 'RETURN' ? $cycle['ODTID'] : null,
            $action === 'RETURN' ? $cycle['DPTID'] : null,
            $pickup['OrderID'] ?? null, $pickup['DeliveryID'] ?? null, $pickup['PickUpID'] ?? null, $batchId]);
        setBottleCycle($db, $bottle['bottleId'], $action === 'LOAD' ? 'LOADED' : 'RETURNED', $accId,
            $cycle['RefillID'], $cycle['ODTID'], $cycle['DPTID']);
    }
    return ['batchId' => $batchId, 'count' => count($verified), 'status' => $action === 'LOAD' ? 'LOADED' : 'RETURNED'];
}

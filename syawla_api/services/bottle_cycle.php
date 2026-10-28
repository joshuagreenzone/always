<?php

require_once __DIR__ . '/bottle_condition.php';
require_once __DIR__ . '/scan_transition.php';
require_once __DIR__ . '/load_trip.php';

const BOTTLE_CYCLE_LABELS = [
    'READY' => 'Ready for Loading', 'LOADED' => 'Loaded for Delivery',
    'DELIVERED' => 'Delivered to Customer', 'COLLECTED' => 'Collected from Customer',
    'RETURNED' => 'Returned to Station'
];

function requireCycleRider(PDO $db, int $accId): void
{
    if (!accountHasRole($db, $accId, 'RIDER')) {
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

function verifyVehicleBottle(PDO $db, int $accId, string $number, string $action, bool $allowCycleJump = false): array
{
    requireCycleRider($db, $accId);
    if (!in_array($action, ['LOAD', 'RETURN', 'DELIVERY'], true)) {
        throw new InvalidArgumentException('Invalid scanning process.');
    }
    $bottle = getBottleCondition($db, $number, $db->inTransaction());
    if (!$bottle && !$db->inTransaction()) {
        $bottle = unregisteredQrPreview($number);
        if ($bottle) return $bottle + ['cycle' => null];
    }
    if (!$bottle) throw new OutOfBoundsException('Bottle not found.');
    $id = $bottle['bottleId'];
    if ($action === 'DELIVERY') {
        if ($allowCycleJump) {
            requireBottleReadyForDelivery($db, $id);
            $cycle = getBottleCycle($db, $id);
            if ($cycle && $cycle['CycleStatus'] === 'LOADED' && (int) $cycle['AccID'] !== $accId) {
                throw new BottleConditionConflict('This bottle was loaded by another rider.');
            }
        }
        else requireLoadedBottle($db, $id, $accId);
        return $bottle + ['cycle' => getBottleCycle($db, $id)];
    }
    requireHealthyBottle($db, $id, $action === 'RETURN');
    $cycle = getBottleCycle($db, $id);
    if ($allowCycleJump) {
        if ($action === 'LOAD' && $cycle && $cycle['CycleStatus'] === 'LOADED' && (int) $cycle['AccID'] !== $accId) {
            throw new BottleConditionConflict('This bottle is loaded by another rider.');
        }
        if ($action === 'RETURN' && $cycle && $cycle['CycleStatus'] === 'COLLECTED') {
            if ((int) $cycle['AccID'] !== $accId) {
                throw new BottleConditionConflict("Bottle {$number} was picked up by another rider. That rider must confirm its return to the station.");
            }
            if (empty($cycle['DPTID'])) {
                throw new BottleConditionConflict("Bottle {$number} has no matching pickup record.");
            }
        }
        return $bottle + ['cycle' => $cycle];
    }
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

function saveVehicleBatch(PDO $db, int $accId, string $action, array $numbers, array $jumpDetails = [], ?array $loadContext = null, ?string $requestKey = null): array
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
    // Consistent lock order; the caller rolls back every failed batch validation.
    ksort($normalized);
    $carried = [];
    $requestHash = hash('sha256', json_encode([$action, $normalized, $jumpDetails, $loadContext], JSON_THROW_ON_ERROR));
    if ($requestKey !== null && !preg_match('/\A[a-zA-Z0-9-]{16,64}\z/', $requestKey)) {
        throw new InvalidArgumentException('Invalid batch request key.');
    }
    // Serializes numbering and concurrent new trips for this rider. Lock this
    // before bottles; the HTTP endpoint uses READ COMMITTED for fresh history.
    $lock = $db->prepare('SELECT AccID FROM accounts WHERE AccID = ? FOR UPDATE');
    $lock->execute([$accId]);
    if ($requestKey !== null) {
        $stmt = $db->prepare('SELECT RequestHash, SavedResult FROM vehicle_scan_batch WHERE AccID = ? AND RequestKey = ? FOR UPDATE');
        $stmt->execute([$accId, $requestKey]);
        if ($saved = $stmt->fetch(PDO::FETCH_ASSOC)) {
            if ($saved['RequestHash'] !== $requestHash) throw new DomainException('This saved batch request was changed. Reopen loading before starting another trip.');
            return json_decode($saved['SavedResult'], true, 512, JSON_THROW_ON_ERROR);
        }
    }
    if ($action === 'LOAD' && $loadContext !== null) {
        $current = getLoadContext($db, $accId);
        // Lock all current and newly scanned bottles in one consistent order.
        $lockNumbers = $normalized;
        foreach ($current['bottles'] as $b) $lockNumbers[strtolower($b['bottleNumber'])] = $b['bottleNumber'];
        ksort($lockNumbers);
        $lock = $db->prepare('SELECT BottleID FROM bottles WHERE BottleNumber = ? FOR UPDATE');
        foreach ($lockNumbers as $n) $lock->execute([$n]);
        $current = getLoadContext($db, $accId);
        if ($current != $loadContext) throw new DomainException('Your previous batch or undelivered bottles changed. Reopen Load for Delivery to review and confirm them again.');
        foreach ($current['bottles'] as $b) {
            $key = strtolower($b['bottleNumber']);
            if (!isset($normalized[$key])) throw new DomainException('All confirmed carry-over bottles must remain in the new batch.');
            $carried[$key] = $b;
        }
    }
    $verified = [];
    $eventType = $action === 'LOAD' ? 'LOAD_SCAN' : 'UNLOAD_SCAN';
    foreach ($normalized as $number) {
        saveUnregisteredQr($db, $number, $accId, (int) ($jumpDetails[strtolower($number)]['bottleTypeId'] ?? 0));
        $bottle = verifyVehicleBottle($db, $accId, $number, $action, true);
        if (isset($carried[strtolower($number)])) {
            // Membership only: this is not another physical loading scan.
            $verified[] = $bottle + ['carryOver' => true, 'sourceBatchId' => $carried[strtolower($number)]['sourceBatchId']];
            continue;
        }
        $details = $jumpDetails[strtolower($number)] ?? [];
        $transition = requireScanTransition($db, $bottle['bottleId'], $eventType,
            $details['jumpReason'] ?? null,
            array_key_exists('previousScanEventId', $details) ? ($details['previousScanEventId'] ?? 0) : null);
        $verified[] = $bottle + ['transition' => $transition];
    }
    [$tripDate, $tripNumber, $batchCode] = $action === 'LOAD' ? nextLoadTrip($db, $accId) : [null, null, null];
    // Whole-second loading times match existing physical scan writers. Passing
    // datetime(6) to datetime previously rounded loads into the next second.
    $stmt = $db->prepare('INSERT INTO vehicle_scan_batch (AccID, Action, BottleCount, ScannedAt, TripDate, TripNumber, BatchCode, RequestKey, RequestHash)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?)');
    $stmt->execute([$accId, $action, count($verified), $tripDate, $tripNumber, $batchCode, $requestKey, $requestHash]);
    $batchId = (int) $db->lastInsertId();
    $eventStmt = $db->prepare('INSERT INTO bottle_scan_event
        (BottleID, AccID, EventType, RefillID, ODTID, DPTID, OrderID, DeliveryID, PickUpID,
         IsCycleJump, PreviousScanEventID, ExpectedPreviousEventType, JumpReason, ScanDateTime)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ScannedAt FROM vehicle_scan_batch WHERE BatchID = ?');
    $pickupStmt = $db->prepare('SELECT p.PickUpID, p.DeliveryID, d.OrderID
        FROM delivery_pickup_transaction dpt
        INNER JOIN pickup p ON p.PickUpID = dpt.PickUpID
        INNER JOIN delivery d ON d.DeliveryID = p.DeliveryID WHERE dpt.DPTID = ?');
    $deliveryStmt = $db->prepare('SELECT odt.OrderID, odt.DeliveryID
        FROM order_delivery_transaction odt WHERE odt.ODTID = ? AND odt.BottleID = ?');
    $stmt = $db->prepare('INSERT INTO vehicle_bottle_scan (BatchID, BottleID, RefillID, DPTID, SourceBatchID, IsCarryOver) VALUES (?, ?, ?, ?, ?, ?)');
    foreach ($verified as $bottle) {
        $cycle = $bottle['cycle'];
        $stmt->execute([$batchId, $bottle['bottleId'], $cycle['RefillID'] ?? null, $action === 'RETURN' ? ($cycle['DPTID'] ?? null) : null, $bottle['sourceBatchId'] ?? null, (int) !empty($bottle['carryOver'])]);
        if (!empty($bottle['carryOver'])) continue;
        $pickup = null;
        if ($action === 'RETURN' && !empty($cycle['DPTID'])) {
            $pickupStmt->execute([$cycle['DPTID']]);
            $pickup = $pickupStmt->fetch(PDO::FETCH_ASSOC);
            if (!$pickup) throw new BottleConditionConflict('The confirmed pickup could not be found.');
        }
        $delivery = null;
        if (($cycle['CycleStatus'] ?? null) === 'DELIVERED' && !empty($cycle['ODTID'])) {
            $deliveryStmt->execute([$cycle['ODTID'], $bottle['bottleId']]);
            $delivery = $deliveryStmt->fetch(PDO::FETCH_ASSOC);
            if (!$delivery) throw new BottleConditionConflict('The delivered bottle could not be matched to its order.');
        }
        $eventStmt->execute([$bottle['bottleId'], $accId, $action === 'LOAD' ? 'LOAD_SCAN' : 'UNLOAD_SCAN',
            $cycle['RefillID'] ?? null,
            $action === 'RETURN' || $delivery ? ($cycle['ODTID'] ?? null) : null,
            $action === 'RETURN' ? ($cycle['DPTID'] ?? null) : null,
            $pickup['OrderID'] ?? $delivery['OrderID'] ?? null,
            $pickup['DeliveryID'] ?? $delivery['DeliveryID'] ?? null, $pickup['PickUpID'] ?? null,
            (int) $bottle['transition']['isCycleJump'], $bottle['transition']['previousScanEventId'],
            $bottle['transition']['expectedPreviousEventType'], $bottle['transition']['jumpReason'], $batchId]);
        setBottleCycle($db, $bottle['bottleId'], $action === 'LOAD' ? 'LOADED' : 'RETURNED', $accId,
            $cycle['RefillID'] ?? null, $cycle['ODTID'] ?? null, $cycle['DPTID'] ?? null);
    }
    $result = ['batchId' => $batchId, 'batchCode' => $batchCode, 'tripNumber' => $tripNumber,
        'count' => count($verified), 'carriedCount' => count($carried), 'newCount' => count($verified) - count($carried),
        'status' => $action === 'LOAD' ? 'LOADED' : 'RETURNED'];
    $db->prepare('UPDATE vehicle_scan_batch SET SavedResult = ? WHERE BatchID = ?')
        ->execute([json_encode($result, JSON_THROW_ON_ERROR), $batchId]);
    return $result;
}

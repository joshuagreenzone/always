<?php

// Development database only; the fixture and every event are rolled back.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/scan_transition.php';

function checkTransition(bool $ok, string $message): void
{
    if (!$ok) throw new RuntimeException($message);
}

$db = (new Database())->connect();
$db->beginTransaction();
try {
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $account = (int) $db->query('SELECT AccID FROM accounts LIMIT 1')->fetchColumn();
    checkTransition($type > 0 && $account > 0, 'A bottle type and account are required.');
    $number = 'JUMP-TEST-' . bin2hex(random_bytes(6));
    $stmt = $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)');
    $stmt->execute([$number, $type]);
    $id = (int) $db->lastInsertId();
    $insert = $db->prepare('INSERT INTO bottle_scan_event
        (BottleID, AccID, EventType, IsCycleJump, PreviousScanEventID,
         ExpectedPreviousEventType, JumpReason) VALUES (?, ?, ?, ?, ?, ?, ?)');

    $first = requireScanTransition($db, $id, 'REFILL_SCAN', null, 0);
    checkTransition(!$first['isCycleJump'], 'First refill should be a normal scan.');
    $previousId = null;
    foreach (['REFILL_SCAN', 'LOAD_SCAN', 'DELIVERY_SCAN', 'PICKUP_SCAN', 'UNLOAD_SCAN'] as $eventType) {
        $transition = requireScanTransition($db, $id, $eventType, null, $previousId ?? 0);
        checkTransition(!$transition['isCycleJump'], "Expected normal transition to {$eventType}.");
        $insert->execute([$id, $account, $eventType, 0, $transition['previousScanEventId'],
            $transition['expectedPreviousEventType'], null]);
        $previousId = (int) $db->lastInsertId();
    }
    $jump = scanTransition($db, $id, 'DELIVERY_SCAN');
    checkTransition($jump['isCycleJump'] && $jump['previousEventType'] === 'UNLOAD_SCAN'
        && $jump['expectedPreviousEventType'] === 'LOAD_SCAN', 'Jump classification is wrong.');
    try {
        requireScanTransition($db, $id, 'DELIVERY_SCAN', '   ', $previousId);
        throw new RuntimeException('Blank reason was accepted.');
    } catch (DomainException $e) {
        checkTransition(str_contains($e->getMessage(), 'reason'), 'Wrong reason error.');
    }
    try {
        requireScanTransition($db, $id, 'DELIVERY_SCAN', 'Emergency replacement', $previousId - 1);
        throw new RuntimeException('Stale previous event was accepted.');
    } catch (DomainException $e) {
        checkTransition(str_contains($e->getMessage(), 'Scan it again'), 'Wrong stale-history error.');
    }
    $jump = requireScanTransition($db, $id, 'DELIVERY_SCAN', 'Emergency replacement', $previousId);
    $insert->execute([$id, $account, 'DELIVERY_SCAN', 1, $jump['previousScanEventId'],
        $jump['expectedPreviousEventType'], $jump['jumpReason']]);
    checkTransition((int) $db->query('SELECT COUNT(*) FROM bottle_scan_event WHERE IsCycleJump = 1
        AND JumpReason = \'Emergency replacement\'')->fetchColumn() === 1,
        'Reasoned jump was not persisted.');
    $db->rollBack();
    echo "Scan transition checks passed; fixtures rolled back.\n";
} finally {
    if ($db->inTransaction()) $db->rollBack();
}

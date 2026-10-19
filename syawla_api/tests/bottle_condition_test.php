<?php

// Run against a local development database after applying the migration:
// php syawla_api/tests/bottle_condition_test.php
// Fixtures and all updates are rolled back; existing bottles are never changed.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_condition.php';

function check(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function expectFailure(string $type, callable $action): void
{
    try {
        $action();
    } catch (Throwable $e) {
        check($e instanceof $type, 'Unexpected error: ' . get_class($e));
        return;
    }
    throw new RuntimeException('Expected failure: ' . $type);
}

$db = (new Database())->connect();
$db->beginTransaction();
try {
    $typeId = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $workerId = (int) $db->query("SELECT AccID FROM account_roles WHERE Role = 'STATION_WORKER' LIMIT 1")->fetchColumn();
    $riderId = (int) $db->query("SELECT AccID FROM account_roles WHERE Role = 'RIDER' LIMIT 1")->fetchColumn();
    $adminId = (int) $db->query("SELECT AccID FROM account_roles WHERE Role = 'ADMIN' LIMIT 1")->fetchColumn();
    check($typeId > 0 && $workerId > 0 && $riderId > 0 && $adminId > 0, 'Development fixtures require bottle types and each staff role.');

    $number = 'STATE-TEST-' . bin2hex(random_bytes(8));
    $stmt = $db->prepare("INSERT INTO bottles (BottleNumber, BottleTypeID, BottleCondition) VALUES (?, ?, 'MISSING')");
    $stmt->execute([$number, $typeId]);
    $bottleId = (int) $db->lastInsertId();
    $insertRefill = $db->prepare('INSERT INTO refill (BottleID, RefillDateTime) VALUES (?, NOW())');
    $insertRefill->execute([$bottleId]);
    $oldRefill = ['RefillID' => (int) $db->lastInsertId(), 'RefillDateTime' => date('Y-m-d H:i:s')];
    $change = fn($acc, $expected, $state, $note) => updateBottleCondition($db, $acc, $number, $expected, $state, $note);

    expectFailure(InvalidArgumentException::class, fn() => $change($workerId, 'MISSING', 'HEALTHY', '   '));
    expectFailure(InvalidArgumentException::class, fn() => $change($workerId, 'MISSING', 'HEALTHY', str_repeat('a', 1001)));
    expectFailure(InvalidArgumentException::class, fn() => $change($workerId, 'MISSING', 'ACTIVE', 'Invalid state'));
    expectFailure(InvalidArgumentException::class, fn() => $change($workerId, 'MISSING', 'MISSING', 'No change'));
    expectFailure(UnexpectedValueException::class, fn() => $change($adminId, 'MISSING', 'HEALTHY', 'Not a scanner role'));
    expectFailure(UnexpectedValueException::class, fn() => $change(0, 'MISSING', 'HEALTHY', 'Invalid account'));
    expectFailure(BottleConditionConflict::class, fn() => requireHealthyBottle($db, $bottleId));
    expectFailure(BottleConditionConflict::class, fn() => requireHealthyBottle($db, $bottleId, true));

    $first = $change($workerId, 'MISSING', 'HEALTHY', ' Found in storage ');
    check($first['condition'] === 'HEALTHY', 'State was not saved.');
    check($first['note'] === 'Found in storage', 'Trimmed note was not saved.');
    check($first['updatedBy'] === $workerId && $first['updatedAt'] !== null, 'Actor or date is missing.');
    requireHealthyBottle($db, $bottleId);
    check($first['needsRefillAfterRecovery'], 'An old refill must not qualify after recovery.');
    expectFailure(BottleConditionConflict::class, fn() => requireBottleReadyForDelivery($db, $bottleId));
    check(canRefillRecoveredBottle($db, $bottleId, $oldRefill), 'A recovered bottle last refilled at the station must allow a replacement refill.');
    // IDs distinguish the new refill even if recovery/refill share a timestamp.
    $insertRefill->execute([$bottleId]);
    check(!bottleNeedsRecoveryRefill($db, $bottleId), 'A fresh refill did not satisfy recovery.');
    requireBottleReadyForDelivery($db, $bottleId);
    check(!canRefillRecoveredBottle($db, $bottleId, $oldRefill), 'Recovery must not permit another duplicate refill.');
    expectFailure(BottleConditionConflict::class, fn() => $change($riderId, 'MISSING', 'DAMAGED', 'Stale scan'));

    $second = $change($riderId, 'HEALTHY', 'DAMAGED', 'Crack found');
    check($second['condition'] === 'DAMAGED' && $second['updatedBy'] === $riderId, 'Rider update failed.');
    expectFailure(BottleConditionConflict::class, fn() => requireHealthyBottle($db, $bottleId));
    requireHealthyBottle($db, $bottleId, true);
    check(getBottleCondition($db, $number)['condition'] === 'DAMAGED', 'Pickup validation must preserve the damaged state.');
    expectFailure(BottleConditionConflict::class, fn() => requireBottleReadyForDelivery($db, $bottleId));
    $stmt = $db->prepare('SELECT PreviousCondition, NewCondition, Note, UpdatedAt FROM bottle_condition_history WHERE BottleID = ? ORDER BY ConditionHistoryID');
    $stmt->execute([$bottleId]);
    $history = $stmt->fetchAll(PDO::FETCH_ASSOC);
    check(count($history) === 2, 'Rejected requests must not create history.');
    check($history[0]['PreviousCondition'] === 'MISSING' && $history[1]['PreviousCondition'] === 'HEALTHY', 'Previous states were not preserved.');
    $change($riderId, 'DAMAGED', 'MISSING', 'Bottle misplaced again');
    $change($workerId, 'MISSING', 'HEALTHY', 'Found and repaired');
    expectFailure(BottleConditionConflict::class, fn() => requireBottleReadyForDelivery($db, $bottleId));
    check(bottleNeedsRecoveryRefill($db, $bottleId), 'A second incident must invalidate the previously valid refill.');
    $insertRefill->execute([$bottleId]);
    requireBottleReadyForDelivery($db, $bottleId);

    $db->rollBack();
    check(getBottleCondition($db, $number) === null, 'Fixture rollback failed.');
    echo "Bottle condition integration checks passed; all fixture changes rolled back.\n";
} finally {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
}

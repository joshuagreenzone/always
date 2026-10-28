<?php
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_cycle.php';
function tripCheck(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
function tripReject(callable $action): void {
    try { $action(); } catch (DomainException | InvalidArgumentException $e) { return; }
    throw new RuntimeException('Expected stale/invalid load to be rejected.');
}
$db = (new Database())->connect();
$db->exec('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
$db->beginTransaction();
try {
    $token = bin2hex(random_bytes(6));
    $db->prepare("INSERT INTO accounts (AccName, AccEmail, AccUsername, AccPassword) VALUES ('Trip test', ?, ?, 'test-only')")
        ->execute(["trip-$token@example.invalid", "trip-$token"]);
    $rider = (int) $db->lastInsertId();
    $db->prepare("INSERT INTO account_roles VALUES (?, 'RIDER')")->execute([$rider]);
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $numbers = [];
    $ids = [];
    $event = $db->prepare('INSERT INTO bottle_scan_event (BottleID, AccID, EventType) VALUES (?, ?, ?)');
    for ($i = 0; $i < 4; $i++) {
        $numbers[] = "TRIP-$token-$i";
        $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)')->execute([$numbers[$i], $type]);
        $ids[] = (int) $db->lastInsertId();
        $db->prepare('INSERT INTO refill (BottleID) VALUES (?)')->execute([$ids[$i]]);
        $event->execute([$ids[$i], $rider, 'REFILL_SCAN']);
    }
    $context = getLoadContext($db, $rider);
    $first = saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 0, 3), [], $context, "$token-first-load");
    tripCheck($first['tripNumber'] === 1 && $first['carriedCount'] === 0, 'First trip numbering failed.');
    tripCheck($first['batchCode'] === DateTimeImmutable::createFromFormat('!Y-m-d', loadTripDate($db))->format('mdy') . '-1', 'Trip format/date incorrect.');
    $db->prepare("INSERT INTO accounts (AccName, AccEmail, AccUsername, AccPassword) VALUES ('Other trip rider', ?, ?, 'test-only')")
        ->execute(["other-trip-$token@example.invalid", "other-trip-$token"]);
    $otherRider = (int) $db->lastInsertId();
    $db->prepare("INSERT INTO account_roles VALUES (?, 'RIDER')")->execute([$otherRider]);
    tripCheck(nextLoadTrip($db, $otherRider)[1] === 1, 'Daily numbering must be independent for each rider.');
    tripReject(fn() => saveVehicleBatch($db, $otherRider, 'LOAD', [$numbers[0]], [], getLoadContext($db, $otherRider), "$token-wrong-rider"));
    $retry = saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 0, 3), [], $context, "$token-first-load");
    tripCheck($retry == $first, 'Network retry created a different trip.');
    tripReject(fn() => saveVehicleBatch($db, $rider, 'LOAD', [$numbers[0]], [], $context, "$token-first-load"));
    $event->execute([$ids[0], $rider, 'DELIVERY_SCAN']);
    $context = getLoadContext($db, $rider);
    tripCheck(count($context['bottles']) === 2, 'Delivered bottle included in carry-over.');
    tripReject(fn() => saveVehicleBatch($db, $rider, 'LOAD', [$numbers[1]], [], $context, "$token-missing-carry"));
    $second = saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 1), [], $context, "$token-second-load");
    tripCheck($second['tripNumber'] === 2 && $second['carriedCount'] === 2 && $second['newCount'] === 1, 'Carry-over totals incorrect.');
    $stmt = $db->prepare('SELECT BatchID, SourceBatchID FROM vehicle_bottle_scan WHERE BottleID = ? ORDER BY BatchID');
    $stmt->execute([$ids[1]]);
    $history = $stmt->fetchAll();
    tripCheck(count($history) === 2 && (int) $history[1]['SourceBatchID'] === $first['batchId'], 'Prior membership lost or source missing.');
    $stmt = $db->prepare("SELECT COUNT(*) FROM bottle_scan_event WHERE BottleID = ? AND EventType = 'LOAD_SCAN'");
    $stmt->execute([$ids[1]]);
    tripCheck((int) $stmt->fetchColumn() === 1, 'Carry-over invented another loading scan.');
    tripReject(fn() => saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 1), [], $context, "$token-stale-batch"));
    $context = getLoadContext($db, $rider);
    $db->exec('SAVEPOINT before_delivery');
    $event->execute([$ids[1], $rider, 'DELIVERY_SCAN']);
    tripReject(fn() => saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 1), [], $context, "$token-stale-delivery"));
    $db->exec('ROLLBACK TO SAVEPOINT before_delivery');
    $third = saveVehicleBatch($db, $rider, 'LOAD', array_slice($numbers, 1), [], $context, "$token-carry-only");
    tripCheck($third['tripNumber'] === 3 && $third['newCount'] === 0 && $third['carriedCount'] === 3, 'Carry-only trip failed.');
    $stmt = $db->prepare('SELECT SourceBatchID FROM vehicle_bottle_scan WHERE BatchID = ? AND BottleID = ?');
    $stmt->execute([$third['batchId'], $ids[1]]);
    tripCheck((int) $stmt->fetchColumn() === $second['batchId'], 'Repeated carry did not point to immediately previous batch.');
    tripCheck(riderLoadTrips($db, $rider)['tripsToday'] === 3, 'Retries/rejections inflated daily trip count.');
    // Midnight in Taipei: date must use UTC+8 even if server timezone changes.
    $db->exec("SET time_zone = '+00:00'");
    $db->exec('SET timestamp = 1793203199.8'); // 2026-10-28 15:59:59 UTC
    tripCheck(loadTripDate($db) === '2026-10-28', 'Taipei date before midnight incorrect.');
    $db->exec('SET timestamp = 1793203200.8');
    tripCheck(loadTripDate($db) === '2026-10-29', 'Taipei daily reset incorrect.');
    tripCheck(nextLoadTrip($db, $rider)[1] === 1, 'Trip numbering did not restart on a new date.');
    echo "Load trip checks passed: history, carry-only, retry, stale confirmation, totals, midnight.\n";
} finally {
    $db->rollBack();
}

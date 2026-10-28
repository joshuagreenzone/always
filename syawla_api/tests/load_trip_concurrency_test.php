<?php
// Uses short-lived committed fixtures so independent worker connections can
// exercise real row locks. Deletes only its own IDs in finally.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_cycle.php';
$db = (new Database())->connect();
if (($argv[1] ?? '') === '--worker') {
    $db->exec('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
    $db->beginTransaction();
    try {
        $result = saveVehicleBatch($db, (int) $argv[2], 'LOAD', [$argv[3]], [],
            json_decode(base64_decode($argv[5]), true), $argv[4]);
        $db->commit();
        echo json_encode(['status' => 'saved', 'batchId' => $result['batchId']]);
    } catch (DomainException $e) {
        $db->rollBack();
        echo json_encode(['status' => 'conflict']);
    }
    exit;
}
function parallelLoads(int $rider, string $number, array $keys, array $context): array {
    $workers = [];
    foreach ($keys as $key) {
        $pipes = [];
        $process = proc_open([PHP_BINARY, __FILE__, '--worker', (string) $rider, $number, $key,
            base64_encode(json_encode($context))], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
        if (!is_resource($process)) throw new RuntimeException('Cannot start concurrent load worker.');
        fclose($pipes[0]);
        $workers[] = [$process, $pipes];
    }
    $results = [];
    foreach ($workers as [$process, $pipes]) {
        $output = stream_get_contents($pipes[1]);
        $error = stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]);
        $code = proc_close($process);
        if ($code !== 0) throw new RuntimeException('Concurrent worker failed: ' . $error);
        $results[] = json_decode($output, true, 512, JSON_THROW_ON_ERROR);
    }
    return $results;
}
$rider = null; $bottle = null;
try {
    $token = bin2hex(random_bytes(8));
    $db->prepare("INSERT INTO accounts (AccName, AccEmail, AccUsername, AccPassword) VALUES ('Concurrency test', ?, ?, 'test-only')")
        ->execute(["trip-$token@example.invalid", "trip-$token"]);
    $rider = (int) $db->lastInsertId();
    $db->prepare("INSERT INTO account_roles VALUES (?, 'RIDER')")->execute([$rider]);
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $number = "TRIP-CONCURRENT-$token";
    $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)')->execute([$number, $type]);
    $bottle = (int) $db->lastInsertId();
    $db->prepare('INSERT INTO refill (BottleID) VALUES (?)')->execute([$bottle]);
    $db->prepare("INSERT INTO bottle_scan_event (BottleID, AccID, EventType) VALUES (?, ?, 'REFILL_SCAN')")->execute([$bottle, $rider]);
    $key = "$token-same-request";
    $results = parallelLoads($rider, $number, [$key, $key], getLoadContext($db, $rider));
    if ($results[0]['status'] !== 'saved' || $results[0] !== $results[1]) throw new RuntimeException('Concurrent retry did not return the same batch.');
    $results = parallelLoads($rider, $number, ["$token-new-one", "$token-new-two"], getLoadContext($db, $rider));
    $statuses = array_column($results, 'status'); sort($statuses);
    if ($statuses !== ['conflict', 'saved']) throw new RuntimeException('Concurrent stale confirmation was not rejected.');
    if (riderLoadTrips($db, $rider)['tripsToday'] !== 2) throw new RuntimeException('Concurrency inflated trip count.');
    echo "Concurrent trip tests passed: identical requests share one trip; competing new trips require reconfirmation.\n";
} finally {
    if ($bottle) {
        $db->prepare('DELETE FROM vehicle_bottle_scan WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('UPDATE bottle_scan_event SET PreviousScanEventID = NULL WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('DELETE FROM bottle_scan_event WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('DELETE FROM bottle_cycle WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('DELETE FROM refill WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('DELETE FROM unregistered_qrs WHERE BottleID = ?')->execute([$bottle]);
        $db->prepare('DELETE FROM bottles WHERE BottleID = ?')->execute([$bottle]);
    }
    if ($rider) {
        $db->prepare('DELETE FROM vehicle_scan_batch WHERE AccID = ?')->execute([$rider]);
        $db->prepare('DELETE FROM account_roles WHERE AccID = ?')->execute([$rider]);
        $db->prepare('DELETE FROM accounts WHERE AccID = ?')->execute([$rider]);
    }
}

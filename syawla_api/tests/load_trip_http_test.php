<?php
// Real local API smoke test. Requires the running CodeIgniter backend path and
// base URL as arguments; all committed fixtures are removed in finally.
$backend = $argv[1] ?? '';
$base = rtrim($argv[2] ?? 'http://127.0.0.1:8081', '/');
if (!is_file($backend . '/app/Config/Paths.php')) throw new RuntimeException('Pass the active CodeIgniter project path.');
define('FCPATH', $backend . '/public/');
define('ENVIRONMENT', 'development');
require $backend . '/app/Config/Paths.php';
$paths = new Config\Paths();
require $paths->systemDirectory . '/Boot.php';
CodeIgniter\Boot::bootConsole($paths);
require_once $backend . '/app/syawla_mobile_api/config/database.php';
$db = (new Database())->connect();
function httpTripCheck(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
$rider = null; $bottle = null;
try {
    $suffix = bin2hex(random_bytes(8));
    $db->prepare("INSERT INTO accounts (AccName, AccEmail, AccUsername, AccPassword) VALUES ('HTTP trip test', ?, ?, 'test-only')")
        ->execute(["http-trip-$suffix@example.invalid", "http-trip-$suffix"]);
    $rider = (int) $db->lastInsertId();
    $db->prepare("INSERT INTO account_roles VALUES (?, 'RIDER')")->execute([$rider]);
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    $number = "HTTP-TRIP-$suffix";
    $db->prepare('INSERT INTO bottles (BottleNumber, BottleTypeID) VALUES (?, ?)')->execute([$number, $type]);
    $bottle = (int) $db->lastInsertId();
    $db->prepare('INSERT INTO refill (BottleID) VALUES (?)')->execute([$bottle]);
    $db->prepare("INSERT INTO bottle_scan_event (BottleID, AccID, EventType) VALUES (?, ?, 'REFILL_SCAN')")->execute([$bottle, $rider]);
    $token = App\Services\MobileToken::issue($rider, 'RIDER');
    $call = static function (string $method, array $body = [], bool $authenticated = true) use ($base, $token): array {
        $url = $base . '/mobile/api/rider/vehicle_bottles.php';
        if ($method === 'GET') $url .= '?' . http_build_query($body);
        $headers = "Content-Type: application/json\r\nAccept: application/json\r\n";
        if ($authenticated) $headers .= "Authorization: Bearer $token\r\n";
        $context = stream_context_create(['http' => ['method' => $method, 'header' => $headers,
            'content' => $method === 'POST' ? json_encode($body) : '', 'ignore_errors' => true, 'timeout' => 15]]);
        $raw = file_get_contents($url, false, $context);
        preg_match('/\s(\d{3})\s/', $http_response_header[0] ?? '', $status);
        return [(int) ($status[1] ?? 0), json_decode($raw, true)];
    };
    [$status] = $call('GET', ['accId' => $rider], false);
    httpTripCheck($status === 401, 'Anonymous request was not rejected.');
    [$status] = $call('GET', ['accId' => $rider + 100000]);
    httpTripCheck($status === 403, 'Wrong rider was not rejected.');
    [$status, $inventory] = $call('GET', ['accId' => $rider]);
    httpTripCheck($status === 200 && isset($inventory['data']['loadContext']), 'Load preview failed: ' . json_encode($inventory));
    $input = ['accId' => $rider, 'action' => 'LOAD', 'bottleNumbers' => [$number],
        'requestKey' => "$suffix-first-load", 'loadContext' => $inventory['data']['loadContext']];
    $bad = $input; unset($bad['loadContext']);
    [$status] = $call('POST', $bad);
    httpTripCheck($status === 400, 'Missing carry-over review was not rejected.');
    $bad = $input;
    $bad['bottleNumbers'][] = "MISSING-TYPE-$suffix";
    [$status] = $call('POST', $bad);
    httpTripCheck($status === 400, 'New external QR without selected type was not rejected.');
    $stmt = $db->prepare('SELECT COUNT(*) FROM unregistered_qrs WHERE QrValue = ?');
    $stmt->execute([$number]);
    httpTripCheck((int) $stmt->fetchColumn() === 0, 'Failed batch left a partial unregistered QR record.');
    [$status, $first] = $call('POST', $input);
    httpTripCheck($status === 200 && $first['data']['tripNumber'] === 1, 'First HTTP load failed: ' . json_encode($first));
    [$status, $retry] = $call('POST', $input);
    httpTripCheck($status === 200 && $retry['data']['batchId'] === $first['data']['batchId'], 'HTTP retry duplicated trip.');
    [$status, $inventory] = $call('GET', ['accId' => $rider]);
    httpTripCheck(count($inventory['data']['loadContext']['bottles']) === 1, 'Undelivered QR missing from confirmation preview.');
    $input['loadContext'] = $inventory['data']['loadContext'];
    $input['requestKey'] = "$suffix-carry-only";
    [$status, $second] = $call('POST', $input);
    httpTripCheck($status === 200 && $second['data']['tripNumber'] === 2 && $second['data']['carriedCount'] === 1, 'HTTP carry-only trip failed: ' . json_encode($second));
    $input['requestKey'] = "$suffix-stale-review";
    [$status] = $call('POST', $input);
    httpTripCheck($status === 409, 'Stale HTTP confirmation was not rejected.');
    [$status, $inventory] = $call('GET', ['accId' => $rider]);
    httpTripCheck($status === 200 && $inventory['data']['tripsToday'] === 2, 'HTTP trip count incorrect.');
    httpTripCheck(count($inventory['data']['trips'][0]['bottles']) === 1, 'Trip history omitted bottle membership.');
    $stmt = $db->prepare("SELECT COUNT(*) FROM bottle_scan_event WHERE BottleID = ? AND EventType = 'LOAD_SCAN'");
    $stmt->execute([$bottle]);
    httpTripCheck((int) $stmt->fetchColumn() === 1, 'HTTP carry-over created a second physical scan.');
    echo "Real HTTP trip tests passed: auth, required confirmation, numbering, retry, carry-only, stale review, history, physical scan count.\n";
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

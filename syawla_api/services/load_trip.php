<?php

// Read-only snapshot for the mandatory carry-over confirmation. Membership is
// historical; current scan state determines which bottles are still in vehicle.
function getLoadContext(PDO $db, int $accId): array
{
    $stmt = $db->prepare("SELECT COALESCE(MAX(BatchID), 0) FROM vehicle_scan_batch WHERE AccID = ? AND Action = 'LOAD'");
    $stmt->execute([$accId]);
    $previous = (int) $stmt->fetchColumn();
    $stmt = $db->prepare("SELECT b.BottleID, b.BottleNumber,
        (SELECT MAX(e.ScanEventID) FROM bottle_scan_event e WHERE e.BottleID = b.BottleID) ScanEventID,
        (SELECT MAX(v.BatchID) FROM vehicle_bottle_scan v JOIN vehicle_scan_batch h ON h.BatchID = v.BatchID
            WHERE v.BottleID = b.BottleID AND h.AccID = ? AND h.Action = 'LOAD') SourceBatchID
        FROM (" . bottleCurrentCycleSql() . ") c JOIN bottles b ON b.BottleID = c.BottleID
        WHERE c.AccID = ? AND c.CycleStatus = 'LOADED' ORDER BY b.BottleID");
    $stmt->execute([$accId, $accId]);
    return ['previousBatchId' => $previous, 'bottles' => array_map(static fn(array $b): array => [
        'bottleId' => (int) $b['BottleID'], 'bottleNumber' => $b['BottleNumber'],
        'scanEventId' => (int) $b['ScanEventID'],
        'sourceBatchId' => $b['SourceBatchID'] === null ? null : (int) $b['SourceBatchID'],
    ], $stmt->fetchAll(PDO::FETCH_ASSOC))];
}

function loadTripDate(PDO $db): string
{
    // Use the database clock with an explicit UTC+8 conversion, independent of
    // PHP/MySQL host timezone and without requiring MySQL timezone tables.
    return $db->query("SELECT DATE(UTC_TIMESTAMP() + INTERVAL 8 HOUR)")->fetchColumn();
}

function nextLoadTrip(PDO $db, int $accId): array
{
    $date = loadTripDate($db);
    // saveVehicleBatch holds the rider account row lock across this allocation.
    $stmt = $db->prepare('SELECT COALESCE(MAX(TripNumber), 0) + 1 FROM vehicle_scan_batch WHERE AccID = ? AND TripDate = ?');
    $stmt->execute([$accId, $date]);
    $number = (int) $stmt->fetchColumn();
    return [$date, $number, DateTimeImmutable::createFromFormat('!Y-m-d', $date)->format('mdy') . '-' . $number];
}

function riderLoadTrips(PDO $db, int $accId): array
{
    $stmt = $db->prepare("SELECT h.BatchID batchId, h.BatchCode batchCode, h.BottleCount count, h.ScannedAt scannedAt,
        h.TripDate tripDate, h.TripNumber tripNumber,
        (SELECT COUNT(*) FROM vehicle_bottle_scan v WHERE v.BatchID = h.BatchID AND v.IsCarryOver = 1) carriedCount
        FROM vehicle_scan_batch h WHERE h.AccID = ? AND h.Action = 'LOAD' ORDER BY h.BatchID DESC LIMIT 30");
    $stmt->execute([$accId]);
    $trips = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($trips as &$trip) {
        $members = $db->prepare('SELECT b.BottleNumber bottleNumber, v.SourceBatchID sourceBatchId, v.IsCarryOver isCarryOver
            FROM vehicle_bottle_scan v JOIN bottles b ON b.BottleID = v.BottleID WHERE v.BatchID = ? ORDER BY b.BottleNumber');
        $members->execute([$trip['batchId']]);
        $trip['bottles'] = $members->fetchAll(PDO::FETCH_ASSOC);
    }
    unset($trip);
    $stmt = $db->prepare("SELECT COUNT(*) FROM vehicle_scan_batch WHERE AccID = ? AND Action = 'LOAD' AND TripDate = ?");
    $stmt->execute([$accId, loadTripDate($db)]);
    return ['trips' => $trips, 'tripsToday' => (int) $stmt->fetchColumn()];
}

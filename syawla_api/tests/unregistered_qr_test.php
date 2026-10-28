<?php
require_once __DIR__ . '/../services/unregistered_qr.php';
function checkQr(bool $ok, string $message): void {
    if (!$ok) throw new RuntimeException($message);
}
foreach (['A-0000', 'RG-0123', 'SG-9999', 'rg-0001'] as $number) {
    checkQr(!isUnregisteredQr($number), 'Supported QR misclassified: ' . $number);
    checkQr(unregisteredQrPreview($number) === null, 'Unknown standard QR must still require registration.');
}
foreach (['external-123', 'RG-other', 'SG', 'A-12345', 'https://bottle/1'] as $number) {
    checkQr(isUnregisteredQr($number), 'External QR misclassified: ' . $number);
    checkQr(unregisteredQrPreview($number)['bottleId'] === 0, 'Preview must not persist a bottle.');
}
foreach (['', str_repeat('x', 201)] as $number) {
    try {
        unregisteredQrPreview($number);
        throw new RuntimeException('Invalid QR accepted.');
    } catch (InvalidArgumentException $e) {}
}
echo "QR classification and preview tests passed.\n";

// Optional development-DB checks; all created rows are rolled back.
if (!in_array('--database', $argv, true)) exit;
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/bottle_cycle.php';
$db = (new Database())->connect();
$db->beginTransaction();
try {
    $rider = (int) $db->query("SELECT AccID FROM account_roles WHERE Role = 'RIDER' LIMIT 1")->fetchColumn();
    checkQr($rider > 0, 'A rider fixture is required.');
    $number = 'external-' . bin2hex(random_bytes(8));
    $type = (int) $db->query('SELECT BottleTypeID FROM bottle_types LIMIT 1')->fetchColumn();
    foreach ([0, -1] as $invalidType) {
        try {
            saveUnregisteredQr($db, $number, $rider, $invalidType);
            throw new RuntimeException('An external QR without a valid type was accepted.');
        } catch (InvalidArgumentException $e) {}
    }
    $db->exec('SAVEPOINT before_qr');
    $saved = saveVehicleBatch($db, $rider, 'LOAD', [$number], [strtolower($number) => [
        'jumpReason' => 'External bottle entered at loading', 'previousScanEventId' => null,
        'bottleTypeId' => $type,
    ]]);
    checkQr($saved['count'] === 1, 'External bottle was not loaded.');
    $stmt = $db->prepare('SELECT BottleID FROM unregistered_qrs WHERE QrValue = ?');
    $stmt->execute([$number]);
    $id = (int) $stmt->fetchColumn();
    checkQr($id > 0, 'Confirmed batch did not record the external QR.');
    $typeStmt = $db->prepare('SELECT BottleTypeID FROM bottles WHERE BottleID = ?');
    $typeStmt->execute([$id]);
    checkQr((int) $typeStmt->fetchColumn() === $type, 'Selected bottle type was not saved.');
    saveUnregisteredQr($db, $number, $rider);
    $stmt = $db->prepare('SELECT COUNT(*) FROM unregistered_qrs WHERE QrValue = ?');
    $stmt->execute([$number]);
    checkQr((int) $stmt->fetchColumn() === 1, 'Repeated scans duplicated the QR.');
    checkQr(getBottleCycle($db, $id)['CycleStatus'] === 'LOADED', 'QR did not enter the bottle workflow.');
    $db->exec('ROLLBACK TO SAVEPOINT before_qr');
    $stmt->execute([$number]);
    checkQr((int) $stmt->fetchColumn() === 0, 'Rolling back a batch left the QR behind.');
    echo "QR batch persistence and rollback tests passed.\n";
} finally {
    $db->rollBack();
}

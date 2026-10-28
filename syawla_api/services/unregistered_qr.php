<?php

// Nonstandard QR values remain identifiable even though workflow foreign keys
// use a shared bottles row. Previewing a QR never creates either record.
function isUnregisteredQr(string $number): bool
{
    return preg_match('/\A(?:A|RG|SG)-[0-9]{4}\z/i', $number) !== 1;
}

function validateScanQr(string $number): void
{
    if ($number === '' || mb_strlen($number, 'UTF-8') > 200) {
        throw new InvalidArgumentException('QR values must contain 1 to 200 characters.');
    }
}

function unregisteredQrPreview(string $number): ?array
{
    validateScanQr($number);
    return isUnregisteredQr($number) ? [
        'bottleId' => 0, 'bottleNumber' => $number, 'condition' => 'HEALTHY',
        'isUnregistered' => true, 'isNewUnregistered' => true,
    ] : null;
}

// The caller owns the batch transaction, including rollback on any validation
// failure. Unique BottleNumber serializes concurrent first saves of one QR.
function saveUnregisteredQr(PDO $db, string $number, int $accId, int $typeId = 0): void
{
    validateScanQr($number);
    if (!isUnregisteredQr($number)) return;
    if (!$db->inTransaction()) throw new LogicException('QR saves require a batch transaction.');
    $stmt = $db->prepare('SELECT BottleID, BottleTypeID FROM bottles WHERE BottleNumber = ? FOR UPDATE');
    $stmt->execute([$number]);
    $bottle = $stmt->fetch(PDO::FETCH_ASSOC);
    $id = $bottle['BottleID'] ?? null;
    if (!$id || empty($bottle['BottleTypeID'])) {
        $stmt = $db->prepare('SELECT BottleTypeID FROM bottle_types WHERE BottleTypeID = ?');
        $stmt->execute([$typeId]);
        if (!$stmt->fetchColumn()) throw new InvalidArgumentException('Choose a valid bottle type for QR ' . $number . '.');
    } elseif ($typeId > 0 && $typeId !== (int) $bottle['BottleTypeID']) {
        throw new DomainException('The bottle type changed. Remove this QR and scan it again.');
    }
    if (!$id) {
        $stmt = $db->prepare("INSERT INTO bottles
            (BottleNumber, BottleTypeID, BottleBrand, BottleRegDateTime)
            VALUES (?, ?, 'Unregistered QR', NOW())");
        $stmt->execute([$number, $typeId]);
        $id = (int) $db->lastInsertId();
    } elseif (empty($bottle['BottleTypeID'])) {
        $db->prepare('UPDATE bottles SET BottleTypeID = ? WHERE BottleID = ?')->execute([$typeId, $id]);
    }
    $stmt = $db->prepare('INSERT INTO unregistered_qrs (BottleID, QrValue, FirstSavedBy)
        VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE BottleID = VALUES(BottleID)');
    $stmt->execute([$id, $number, $accId]);
}

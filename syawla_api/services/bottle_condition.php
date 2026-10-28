<?php

require_once __DIR__ . '/account_roles.php';
require_once __DIR__ . '/bottle_repair.php';
require_once __DIR__ . '/unregistered_qr.php';

class BottleConditionConflict extends DomainException {}

function requireBottleConditionAccount(PDO $db, int $accId): void
{
    if (!accountHasRole($db, $accId, 'STATION_WORKER') && !accountHasRole($db, $accId, 'RIDER')) {
        throw new UnexpectedValueException('Only station workers and riders can update bottle states.');
    }
}

function getBottleCondition(PDO $db, string $number, bool $lock = false): ?array
{
    $stmt = $db->prepare('
        SELECT BottleID, BottleNumber, BottleCondition, BottleOwner, BottleTypeID
        FROM bottles WHERE BottleNumber = :number LIMIT 1
        ' . ($lock ? 'FOR UPDATE' : ''));
    $stmt->execute([':number' => $number]);
    $bottle = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$bottle) {
        return null;
    }

    $stmt = $db->prepare('
        SELECT ConditionHistoryID, Note, UpdatedAt, AccID
        FROM bottle_condition_history WHERE BottleID = :bottleId
        ORDER BY ConditionHistoryID DESC LIMIT 1');
    $stmt->execute([':bottleId' => $bottle['BottleID']]);
    $history = $stmt->fetch(PDO::FETCH_ASSOC);
    $partsUsed = [];
    if ($history) {
        $stmt = $db->prepare("SELECT s.SupplyName name,m.SupplyID supplyId,-m.QuantityChange quantity,m.MovementID movementId
            FROM inventory_supply_movement m JOIN inventory_supply s ON s.SupplyID=m.SupplyID
            WHERE m.RequestKey LIKE ? AND m.RequestKey=CONCAT('repair-',?,'-',m.SupplyID) ORDER BY m.SupplyID");
        $stmt->execute(['repair-'.$history['ConditionHistoryID'].'-%',$history['ConditionHistoryID']]);
        $partsUsed = $stmt->fetchAll(PDO::FETCH_ASSOC);
    }

    return [
        'bottleId' => (int) $bottle['BottleID'],
        'isUnregistered' => isUnregisteredQr($bottle['BottleNumber']),
        'isNewUnregistered' => isUnregisteredQr($bottle['BottleNumber']) && empty($bottle['BottleTypeID']),
        'bottleNumber' => $bottle['BottleNumber'],
        'bottleOwner' => $bottle['BottleOwner'],
        'condition' => $bottle['BottleCondition'],
        'repairParts' => $bottle['BottleCondition'] === 'HEALTHY' ? [] : bottleRepairParts($db,(int)$bottle['BottleID']),
        'partsUsed' => count($partsUsed),
        'repairPartsUsed' => $partsUsed,
        'note' => $history['Note'] ?? null,
        'updatedAt' => $history['UpdatedAt'] ?? null,
        'updatedBy' => isset($history['AccID']) ? (int) $history['AccID'] : null,
        'needsRefillAfterRecovery' => bottleNeedsRecoveryRefill($db, (int) $bottle['BottleID'])
    ];
}

// The caller owns the transaction. Locking the bottle serializes condition changes
// with delivery, pickup, and refill confirmations that lock the same row.
function updateBottleCondition(
    PDO $db,
    int $accId,
    string $number,
    string $expectedCondition,
    string $newCondition,
    string $note,
    array $repairSupplyIds = [],
    bool $allowAdmin = false
): array {
    if (!$db->inTransaction()) {
        throw new LogicException('A bottle state update requires a transaction.');
    }
    if (!$allowAdmin || !accountHasRole($db,$accId,'ADMIN')) requireBottleConditionAccount($db, $accId);
    $conditions = ['HEALTHY', 'MISSING', 'DAMAGED'];
    if (!in_array($expectedCondition, $conditions, true) ||
        !in_array($newCondition, $conditions, true)) {
        throw new InvalidArgumentException('Invalid bottle state.');
    }
    $note = trim($note);
    if ($note === '' || mb_strlen($note, 'UTF-8') > 1000) {
        throw new InvalidArgumentException('A note of 1 to 1000 characters is required.');
    }
    $bottle = getBottleCondition($db, $number, true);
    if (!$bottle) {
        throw new OutOfBoundsException('Bottle not found.');
    }
    if ($bottle['condition'] !== $expectedCondition) {
        throw new BottleConditionConflict('The bottle state changed. Scan the bottle again to review its latest state.');
    }
    if ($newCondition === $expectedCondition) {
        throw new InvalidArgumentException('Choose a different bottle state.');
    }

    if ($repairSupplyIds && ($newCondition !== 'HEALTHY' || $expectedCondition === 'HEALTHY')) {
        throw new InvalidArgumentException('Replacement parts can only be recorded when restoring an unhealthy bottle to Healthy.');
    }

    $stmt = $db->prepare('SELECT RefillID FROM refill WHERE BottleID = :id ORDER BY RefillID DESC LIMIT 1 FOR UPDATE');
    $stmt->execute([':id' => $bottle['bottleId']]);
    $refillIdAtUpdate = (int) $stmt->fetchColumn();
    $stmt = $db->prepare('UPDATE bottles SET BottleCondition = :condition WHERE BottleID = :bottleId');
    $stmt->execute([':condition' => $newCondition, ':bottleId' => $bottle['bottleId']]);
    $stmt = $db->prepare('
        INSERT INTO bottle_condition_history
            (BottleID, AccID, PreviousCondition, NewCondition, Note, UpdatedAt, RefillIDAtUpdate)
        VALUES (:bottleId, :accId, :previous, :condition, :note, CURRENT_TIMESTAMP(6), :refillId)');
    $stmt->execute([
        ':bottleId' => $bottle['bottleId'],
        ':accId' => $accId,
        ':previous' => $expectedCondition,
        ':condition' => $newCondition,
        ':note' => $note,
        ':refillId' => $refillIdAtUpdate
    ]);
    $historyId = (int)$db->lastInsertId();
    consumeBottleRepairParts($db,$bottle['bottleId'],$number,$historyId,$accId,$repairSupplyIds);
    $result = getBottleCondition($db, $number);
    $result['partsUsed'] = count($repairSupplyIds);
    return $result;
}

function requireHealthyBottle(PDO $db, int $bottleId, bool $allowDamagedPickup = false): void
{
    // A locking read sees the latest state even if this transaction established
    // a repeatable-read snapshot before another scanner changed the bottle.
    $stmt = $db->prepare('SELECT BottleNumber, BottleCondition FROM bottles WHERE BottleID = :id'
        . ($db->inTransaction() ? ' FOR UPDATE' : ''));
    $stmt->execute([':id' => $bottleId]);
    $bottle = $stmt->fetch(PDO::FETCH_ASSOC);
    $allowed = $allowDamagedPickup ? ['HEALTHY', 'DAMAGED'] : ['HEALTHY'];
    if (!$bottle || !in_array($bottle['BottleCondition'], $allowed, true)) {
        $state = strtolower($bottle['BottleCondition'] ?? 'unknown');
        $number = $bottle['BottleNumber'] ?? (string) $bottleId;
        throw new BottleConditionConflict(
            "Bottle {$number} is {$state}. Scan it again to review and update its state before continuing."
        );
    }
}

function bottleNeedsRecoveryRefill(PDO $db, int $bottleId): bool
{
    $lock = $db->inTransaction() ? ' FOR UPDATE' : '';
    $stmt = $db->prepare("SELECT RefillIDAtUpdate FROM bottle_condition_history
        WHERE BottleID = :id AND NewCondition = 'HEALTHY'
          AND PreviousCondition IN ('MISSING', 'DAMAGED')
        ORDER BY ConditionHistoryID DESC LIMIT 1" . $lock);
    $stmt->execute([':id' => $bottleId]);
    $cutoff = $stmt->fetchColumn();
    if ($cutoff === false) {
        return false;
    }
    $stmt = $db->prepare('SELECT RefillID FROM refill WHERE BottleID = :id ORDER BY RefillID DESC LIMIT 1' . $lock);
    $stmt->execute([':id' => $bottleId]);
    return (int) $stmt->fetchColumn() <= (int) $cutoff;
}

function requireBottleReadyForDelivery(PDO $db, int $bottleId): void
{
    requireHealthyBottle($db, $bottleId);
    if (bottleNeedsRecoveryRefill($db, $bottleId)) {
        throw new BottleConditionConflict('This bottle was restored to healthy after being missing or damaged. Refill it again before delivery.');
    }
}

// Permit the necessary replacement refill when the bottle's last known use
// was a refill at the station. A recovery must not bypass an outward movement.
function canRefillRecoveredBottle(PDO $db, int $bottleId, $latestRefill): bool
{
    if (!$latestRefill || !bottleNeedsRecoveryRefill($db, $bottleId)) {
        return false;
    }
    $stmt = $db->prepare("SELECT 1 FROM order_delivery_transaction odt
        INNER JOIN delivery d ON d.DeliveryID = odt.DeliveryID
        WHERE odt.BottleID = :id AND d.DeliveryDateTime >= :refilledAt LIMIT 1");
    $stmt->execute([':id' => $bottleId, ':refilledAt' => $latestRefill['RefillDateTime']]);
    if ($stmt->fetchColumn()) {
        return false;
    }
    $stmt = $db->prepare("SELECT 1 FROM premise_bottle_movement
        WHERE BottleID = :id AND MovementType = 'RELEASE'
          AND MovementDateTime >= :refilledAt LIMIT 1");
    $stmt->execute([':id' => $bottleId, ':refilledAt' => $latestRefill['RefillDateTime']]);
    return !$stmt->fetchColumn();
}

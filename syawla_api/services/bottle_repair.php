<?php

/** Replacement hardware is counted with caps; refill seals are a separate supply. */
function bottleRepairParts(PDO $db, int $bottleId): array
{
    $stmt = $db->prepare('SELECT bt.BottleType FROM bottles b JOIN bottle_types bt ON bt.BottleTypeID=b.BottleTypeID WHERE b.BottleID=?');
    $stmt->execute([$bottleId]);
    $type = (string)$stmt->fetchColumn();
    $parts = $db->query("SELECT SupplyID,SupplyCode,SupplyName,QuantityOnHand FROM inventory_supply WHERE Category='CAP' ORDER BY SupplyID")->fetchAll(PDO::FETCH_ASSOC);
    $result = [];
    foreach ($parts as $part) {
        $code = $part['SupplyCode'];
        if ($code === 'CAP_ROUND' && stripos($type,'round') === false) continue;
        if (in_array($code,['CAP_SLIM_BIG','CAP_SLIM_SMALL','SPIGOT_SLIM'],true) && stripos($type,'slim') === false) continue;
        $result[] = ['supplyId'=>(int)$part['SupplyID'],'code'=>$code,'name'=>$part['SupplyName'],'quantityOnHand'=>(int)$part['QuantityOnHand']];
    }
    return $result;
}

/** Caller owns the condition-change transaction and already holds the bottle lock. */
function consumeBottleRepairParts(PDO $db, int $bottleId, string $number, int $historyId, int $actor, array $ids): void
{
    if (!$db->inTransaction()) throw new LogicException('Bottle repairs require a transaction.');
    if (!$ids) return;
    if (count($ids)>20) throw new InvalidArgumentException('Select at most 20 replacement parts.');
    $normalized = [];
    foreach ($ids as $id) {
        $id = (is_int($id) || is_string($id)) ? filter_var($id,FILTER_VALIDATE_INT) : false;
        if (!$id || $id<1 || isset($normalized[$id])) throw new InvalidArgumentException('Select each replacement part only once.');
        $normalized[$id] = $id;
    }
    ksort($normalized, SORT_NUMERIC);
    $allowed = array_column(bottleRepairParts($db,$bottleId),'supplyId');
    foreach ($normalized as $id) {
        if (!in_array($id,$allowed,true)) throw new InvalidArgumentException('This replacement part does not match the bottle type.');
        $stmt = $db->prepare("SELECT * FROM inventory_supply WHERE SupplyID=? AND Category='CAP' FOR UPDATE");
        $stmt->execute([$id]);
        $part = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$part || (int)$part['QuantityOnHand']<1) throw new DomainException('Not enough stock for '.($part['SupplyName'] ?? 'the selected part').'. Receive stock before saving this repair.');
        $before = (int)$part['QuantityOnHand'];
        $key = 'repair-'.$historyId.'-'.$id;
        $stmt = $db->prepare("INSERT INTO inventory_supply_movement (SupplyID,MovementType,QuantityChange,QuantityBefore,QuantityAfter,UnitCost,OccurredAt,RecordedByAccID,Notes,RequestKey,PayloadHash) VALUES (?,'USAGE',-1,?,?,?,CURRENT_TIMESTAMP(6),?,?,?,?)");
        $stmt->execute([$id,$before,$before-1,$part['AverageUnitCost'],$actor,'Bottle repair #'.$historyId.', bottle '.$number,$key,hash('sha256',$key)]);
        $db->prepare('UPDATE inventory_supply SET QuantityOnHand=QuantityOnHand-1 WHERE SupplyID=?')->execute([$id]);
    }
}

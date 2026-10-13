<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_cycle.php';

try {
    $db = (new Database())->connect();
    // Ready stock is the current confirmed refill cycle, not a historical refill.
    $stmt = $db->query("SELECT r.RefillID, r.BottleID, r.RefillDateTime,
        b.BottleNumber, b.BottleTypeID, bt.BottleType, bt.Price
        FROM (" . bottleCurrentCycleSql() . ") c INNER JOIN bottles b ON b.BottleID = c.BottleID
        INNER JOIN refill r ON r.RefillID = c.RefillID AND r.BottleID = c.BottleID
        INNER JOIN bottle_types bt ON bt.BottleTypeID = b.BottleTypeID
        WHERE c.CycleStatus = 'READY' AND b.BottleCondition = 'HEALTHY'
        AND NOT EXISTS (SELECT 1 FROM bottle_condition_history h
            WHERE h.BottleID = b.BottleID AND h.NewCondition = 'HEALTHY'
              AND h.PreviousCondition IN ('MISSING', 'DAMAGED')
              AND h.RefillIDAtUpdate >= r.RefillID)
        ORDER BY r.RefillDateTime DESC, r.RefillID DESC");
    echo json_encode(['success' => true, 'data' => $stmt->fetchAll(PDO::FETCH_ASSOC)]);
} catch (Throwable $e) {
    error_log('Ready bottle inventory: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Unable to load ready bottles.']);
}

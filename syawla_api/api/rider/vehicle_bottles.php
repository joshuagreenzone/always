<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_cycle.php';
$db = null;
try {
    $db = (new Database())->connect();
    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $accId = (int) ($_GET['accId'] ?? 0);
        requireCycleRider($db, $accId);
        if (isset($_GET['bottleNumber'])) {
            $data = verifyVehicleBottle($db, $accId, trim((string) $_GET['bottleNumber']), (string) ($_GET['action'] ?? ''));
        } else {
            $stmt = $db->prepare("SELECT b.BottleNumber AS bottleNumber, b.BottleCondition AS `condition`,
                c.CycleStatus AS status, c.UpdatedAt AS updatedAt
                FROM (" . bottleCurrentCycleSql() . ") c INNER JOIN bottles b ON b.BottleID = c.BottleID
                WHERE c.AccID = ? AND c.CycleStatus IN ('LOADED', 'COLLECTED') ORDER BY c.UpdatedAt DESC");
            $stmt->execute([$accId]);
            $bottles = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $stmt = $db->prepare("SELECT BatchID AS batchId, BottleCount AS count, ScannedAt AS scannedAt
                FROM vehicle_scan_batch WHERE AccID = ? AND Action = 'RETURN' ORDER BY BatchID DESC LIMIT 10");
            $stmt->execute([$accId]);
            $data = ['bottles' => $bottles, 'returns' => $stmt->fetchAll(PDO::FETCH_ASSOC), 'labels' => BOTTLE_CYCLE_LABELS];
        }
    } elseif ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = json_decode(file_get_contents('php://input'), true);
        if (!is_array($input) || !is_array($input['bottleNumbers'] ?? null)) throw new InvalidArgumentException('Bottle numbers are required.');
        $db->beginTransaction();
        $data = saveVehicleBatch($db, (int) ($input['accId'] ?? 0), (string) ($input['action'] ?? ''), $input['bottleNumbers']);
        $db->commit();
    } else {
        http_response_code(405);
        header('Allow: GET, POST');
        echo json_encode(['success' => false, 'message' => 'Use GET or POST.']);
        exit;
    }
    echo json_encode(['success' => true, 'data' => $data]);
} catch (Throwable $e) {
    if ($db !== null && $db->inTransaction()) $db->rollBack();
    $status = $e instanceof InvalidArgumentException ? 400 : ($e instanceof UnexpectedValueException ? 403
        : ($e instanceof OutOfBoundsException ? 404 : ($e instanceof DomainException ? 409 : 500)));
    http_response_code($status);
    if ($status === 500) error_log('Vehicle scanning: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => $status === 500 ? 'Unable to process vehicle bottles. No scans were saved.' : $e->getMessage()]);
}

<?php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/dispenser_workflow.php';
try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) throw new InvalidArgumentException('Invalid maintenance request.');
    $accId = (int) ($input['accId'] ?? 0);
    $db = (new Database())->connect();
    $role = $db->prepare("SELECT 1 FROM account_roles WHERE AccID = ? AND Role IN ('RIDER','STATION_WORKER') LIMIT 1");
    $role->execute([$accId]);
    if (!$role->fetchColumn()) throw new DomainException('Account cannot record maintenance.');
    $input['performedByAccId'] = $accId;
    $input['verificationMethod'] = 'SCAN';
    echo json_encode(['success' => true, 'data' => (new DispenserWorkflow($db))->maintenance($input, $accId)]);
} catch (Throwable $e) {
    $status = $e instanceof InvalidArgumentException ? 400 : ($e instanceof DomainException ? 409 : ($e instanceof OutOfBoundsException ? 404 : 500));
    http_response_code($status);
    if ($status === 500) error_log('Dispenser maintenance: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => $status === 500 ? 'Unable to save maintenance.' : $e->getMessage()]);
}

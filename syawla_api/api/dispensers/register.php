<?php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/dispenser_workflow.php';

try {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        header('Allow: POST');
        echo json_encode(['success' => false, 'message' => 'Use POST to register a dispenser.']);
        exit;
    }
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) throw new InvalidArgumentException('Invalid registration request.');
    $db = (new Database())->connect();
    $role = $db->prepare("SELECT 1 FROM account_roles WHERE AccID = ? AND Role = 'STATION_WORKER' LIMIT 1");
    $role->execute([(int) ($input['accId'] ?? 0)]);
    if (!$role->fetchColumn()) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'Only station workers can register dispensers.']);
        exit;
    }
    foreach (['brand', 'model'] as $field) {
        if (!is_string($input[$field] ?? '') || mb_strlen(trim($input[$field] ?? '')) > 100) {
            throw new InvalidArgumentException('Brand and model must be at most 100 characters.');
        }
    }
    $dispenser = (new DispenserWorkflow($db))->register($input);
    echo json_encode(['success' => true, 'data' => $dispenser]);
} catch (Throwable $e) {
    $duplicate = $e instanceof PDOException && ($e->errorInfo[1] ?? null) === 1062;
    $status = $e instanceof InvalidArgumentException ? 400 : ($e instanceof DomainException || $duplicate ? 409 : 500);
    http_response_code($status);
    if ($status === 500) error_log('Dispenser registration: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => $duplicate ? 'Dispenser number is already registered.' : ($status === 500 ? 'Unable to register dispenser.' : $e->getMessage())]);
}

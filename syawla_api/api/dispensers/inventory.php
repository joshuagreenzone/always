<?php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/dispenser_workflow.php';
try {
    $workflow = new DispenserWorkflow((new Database())->connect());
    echo json_encode(['success' => true, 'data' => $workflow->inventory()]);
} catch (Throwable $e) {
    error_log('Dispenser inventory: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Unable to load dispensers.']);
}

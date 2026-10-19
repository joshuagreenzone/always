<?php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/dispenser_workflow.php';
try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) throw new InvalidArgumentException('Invalid scan request.');
    $workflow = new DispenserWorkflow((new Database())->connect());
    echo json_encode(['success' => true, 'data' => $workflow->scan($input)]);
} catch (Throwable $e) {
    $status = $e instanceof InvalidArgumentException ? 400 : ($e instanceof DomainException ? 409 : ($e instanceof OutOfBoundsException ? 404 : 500));
    http_response_code($status);
    if ($status === 500) error_log('Dispenser scan: ' . $e->getMessage());
    echo json_encode(['success' => false, 'message' => $status === 500 ? 'Unable to save dispenser scan.' : $e->getMessage()]);
}

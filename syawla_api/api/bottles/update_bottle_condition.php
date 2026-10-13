<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_condition.php';

$db = null;
try {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        http_response_code(405);
        header('Allow: POST');
        echo json_encode(['success' => false, 'message' => 'Use POST to update bottle states.']);
        exit;
    }
    $input = json_decode(file_get_contents('php://input'), true);
    if (!is_array($input)) {
        throw new InvalidArgumentException('Invalid request body.');
    }
    foreach (['bottleNumber', 'expectedCondition', 'condition', 'note'] as $field) {
        if (!isset($input[$field]) || !is_string($input[$field])) {
            throw new InvalidArgumentException('Bottle number, states, and a note are required.');
        }
    }
    $accId = (int) ($input['accId'] ?? 0);
    $number = trim($input['bottleNumber']);
    if ($accId <= 0 || $number === '' || strlen($number) > 200) {
        throw new InvalidArgumentException('Account ID and bottle number are required.');
    }
    $db = (new Database())->connect();
    $db->beginTransaction();
    $bottle = updateBottleCondition(
        $db, $accId, $number, $input['expectedCondition'], $input['condition'], $input['note']
    );
    $db->commit();
    echo json_encode(['success' => true, 'message' => 'Bottle state updated.', 'data' => $bottle]);
} catch (Throwable $e) {
    if ($db !== null && $db->inTransaction()) {
        $db->rollBack();
    }
    $status = $e instanceof InvalidArgumentException ? 400
        : ($e instanceof UnexpectedValueException ? 403
        : ($e instanceof OutOfBoundsException ? 404
        : ($e instanceof BottleConditionConflict ? 409 : 500)));
    http_response_code($status);
    if ($status === 500) {
        error_log('Bottle state update: ' . $e->getMessage());
    }
    echo json_encode(['success' => false, 'message' => $status === 500
        ? 'Unable to save the bottle state. No changes were saved.' : $e->getMessage()]);
}

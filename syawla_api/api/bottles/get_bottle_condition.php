<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_condition.php';

try {
    $number = trim((string) ($_GET['bottleNumber'] ?? ''));
    $accId = (int) ($_GET['accId'] ?? 0);
    if ($number === '' || strlen($number) > 200 || $accId <= 0) {
        throw new InvalidArgumentException('Account ID and bottle number are required.');
    }
    $db = (new Database())->connect();
    requireBottleConditionAccount($db, $accId);
    $bottle = getBottleCondition($db, $number);
    if (!$bottle) {
        throw new OutOfBoundsException('Bottle not found.');
    }
    echo json_encode(['success' => true, 'data' => $bottle]);
} catch (Throwable $e) {
    $status = $e instanceof InvalidArgumentException ? 400
        : ($e instanceof UnexpectedValueException ? 403
        : ($e instanceof OutOfBoundsException ? 404 : 500));
    http_response_code($status);
    if ($status === 500) {
        error_log('Bottle state lookup: ' . $e->getMessage());
    }
    echo json_encode(['success' => false, 'message' => $status === 500
        ? 'Unable to load the bottle state.' : $e->getMessage()]);
}

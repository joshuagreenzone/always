<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/scan_transition.php';

try {
    $number = trim((string) ($_GET['bottleNumber'] ?? ''));
    $eventType = (string) ($_GET['eventType'] ?? '');
    if ($number === '' || !isset(SCAN_EXPECTED_PREVIOUS[$eventType])) {
        throw new InvalidArgumentException('Bottle number and scan type are required.');
    }
    $db = (new Database())->connect();
    $stmt = $db->prepare('SELECT BottleID FROM bottles WHERE BottleNumber = ?');
    $stmt->execute([$number]);
    $id = $stmt->fetchColumn();
    if (!$id) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Bottle not found.']);
        exit;
    }
    echo json_encode(['success' => true, 'data' => scanTransition($db, (int) $id, $eventType)]);
} catch (InvalidArgumentException $e) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
} catch (Throwable $e) {
    error_log('Scan transition: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Unable to check the bottle scan history.']);
}

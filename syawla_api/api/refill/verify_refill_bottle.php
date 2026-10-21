<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_condition.php';

try {
    $number = trim((string) ($_GET['bottleNumber'] ?? ''));
    if ($number === '') throw new InvalidArgumentException('Bottle number is required.');
    $db = (new Database())->connect();
    $stmt = $db->prepare('SELECT b.BottleID, b.BottleNumber, b.BottleTypeID,
        b.BottleRegDateTime, b.BottleOwner, bt.BottleType, bt.Price
        FROM bottles b INNER JOIN bottle_types bt ON bt.BottleTypeID = b.BottleTypeID
        WHERE b.BottleNumber = ? LIMIT 1');
    $stmt->execute([$number]);
    $bottle = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$bottle) {
        http_response_code(404);
        echo json_encode(['success' => false, 'message' => 'Bottle not found.']);
        exit;
    }
    requireHealthyBottle($db, (int) $bottle['BottleID']);
    echo json_encode(['success' => true, 'data' => $bottle]);
} catch (InvalidArgumentException $e) {
    http_response_code(400);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
} catch (BottleConditionConflict $e) {
    http_response_code(409);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
} catch (Throwable $e) {
    error_log('Refill verification: ' . $e->getMessage());
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Unable to verify bottle.']);
}

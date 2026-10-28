<?php

header('Content-Type: application/json');
require_once __DIR__ . '/../../config/database.php';
require_once __DIR__ . '/../../services/bottle_condition.php';
require_once __DIR__ . '/../../services/scan_transition.php';
require_once __DIR__ . '/../../services/bottle_cycle.php';

try {
    $number = trim((string) ($_GET['bottleNumber'] ?? ''));
    $accId = (int) ($_GET['accId'] ?? 0);
    if ($number === '' || strlen($number) > 200 || $accId <= 0) {
        throw new InvalidArgumentException('Account ID and bottle number are required.');
    }
    $db = (new Database())->connect();
    requireBottleConditionAccount($db, $accId);
    $bottle = getBottleCondition($db, $number);
    if (!$bottle && ($preview = unregisteredQrPreview($number))) {
        $eventType = (string) ($_GET['eventType'] ?? '');
        if (!isset(SCAN_EXPECTED_PREVIOUS[$eventType])) {
            throw new InvalidArgumentException('Invalid scan type.');
        }
        $preview['transition'] = [
            'isCycleJump' => $eventType !== 'REFILL_SCAN',
            'previousScanEventId' => null,
            'previousEventType' => null,
            'expectedPreviousEventType' => SCAN_EXPECTED_PREVIOUS[$eventType],
        ];
        $preview['vehicle'] = $preview;
        echo json_encode(['success' => true, 'data' => $preview]);
        exit;
    }
    if (!$bottle) {
        throw new OutOfBoundsException('Bottle not found.');
    }
    // A scanner needs both state and history; return them in one round trip.
    $eventType = (string) ($_GET['eventType'] ?? '');
    if ($eventType !== '') {
        if (!isset(SCAN_EXPECTED_PREVIOUS[$eventType])) {
            throw new InvalidArgumentException('Invalid scan type.');
        }
        $bottle['transition'] = scanTransition($db, $bottle['bottleId'], $eventType);
        $action = ['LOAD_SCAN' => 'LOAD', 'UNLOAD_SCAN' => 'RETURN', 'DELIVERY_SCAN' => 'DELIVERY'][$eventType] ?? null;
        // Unhealthy bottles still use the existing recovery dialog first.
        if ($action !== null && $bottle['condition'] === 'HEALTHY') {
            requireCycleRider($db, $accId);
            $bottle['vehicle'] = verifyVehicleBottle($db, $accId, $number, $action, true);
        }
    }
    echo json_encode(['success' => true, 'data' => $bottle]);
} catch (Throwable $e) {
    $status = $e instanceof InvalidArgumentException ? 400
        : ($e instanceof UnexpectedValueException ? 403
        : ($e instanceof OutOfBoundsException ? 404 : ($e instanceof DomainException ? 409 : 500)));
    http_response_code($status);
    if ($status === 500) {
        error_log('Bottle state lookup: ' . $e->getMessage());
    }
    echo json_encode(['success' => false, 'message' => $status === 500
        ? 'Unable to load the bottle state.' : $e->getMessage()]);
}

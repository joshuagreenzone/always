<?php

const SCAN_EXPECTED_PREVIOUS = [
    'LOAD_SCAN' => 'REFILL_SCAN',
    'DELIVERY_SCAN' => 'LOAD_SCAN',
    'PICKUP_SCAN' => 'DELIVERY_SCAN',
    'UNLOAD_SCAN' => 'PICKUP_SCAN',
    'REFILL_SCAN' => 'UNLOAD_SCAN',
];

function scanTransition(PDO $db, int $bottleId, string $eventType): array
{
    if (!isset(SCAN_EXPECTED_PREVIOUS[$eventType])) {
        throw new InvalidArgumentException('Unknown scan event type.');
    }
    $stmt = $db->prepare('SELECT ScanEventID, EventType FROM bottle_scan_event
        WHERE BottleID = ? ORDER BY ScanDateTime DESC, ScanEventID DESC LIMIT 1');
    $stmt->execute([$bottleId]);
    $previous = $stmt->fetch(PDO::FETCH_ASSOC) ?: null;
    $expected = SCAN_EXPECTED_PREVIOUS[$eventType];
    $jump = $previous ? $previous['EventType'] !== $expected : $eventType !== 'REFILL_SCAN';
    return [
        'isCycleJump' => $jump,
        'previousScanEventId' => $previous ? (int) $previous['ScanEventID'] : null,
        'previousEventType' => $previous['EventType'] ?? null,
        'expectedPreviousEventType' => $expected,
    ];
}

function requireScanTransition(PDO $db, int $bottleId, string $eventType, $reason, $previousId): array
{
    $transition = scanTransition($db, $bottleId, $eventType);
    $actualId = $transition['previousScanEventId'];
    if ($previousId !== null && (!is_numeric($previousId) || (int) $previousId !== ($actualId ?? 0))) {
        throw new DomainException('The bottle was scanned elsewhere. Scan it again to review its latest step.');
    }
    if ($transition['isCycleJump']) {
        if (!is_string($reason) || trim($reason) === '') {
            throw new DomainException('Give a reason for skipping the expected bottle scan step.');
        }
        if (mb_strlen(trim($reason)) > 1000) {
            throw new InvalidArgumentException('The scan jump reason must be 1000 characters or fewer.');
        }
    }
    $transition['jumpReason'] = $transition['isCycleJump'] ? trim($reason) : null;
    return $transition;
}

CREATE TABLE IF NOT EXISTS bottle_cycle (
    BottleID BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    CycleStatus ENUM('READY','LOADED','DELIVERED','COLLECTED','RETURNED') NOT NULL,
    AccID BIGINT UNSIGNED NULL,
    RefillID BIGINT UNSIGNED NULL,
    ODTID BIGINT UNSIGNED NULL,
    DPTID BIGINT UNSIGNED NULL,
    UpdatedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    KEY idx_cycle_rider (AccID, CycleStatus),
    FOREIGN KEY (BottleID) REFERENCES bottles(BottleID),
    FOREIGN KEY (AccID) REFERENCES accounts(AccID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS vehicle_scan_batch (
    BatchID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    AccID BIGINT UNSIGNED NOT NULL,
    Action ENUM('LOAD','RETURN') NOT NULL,
    BottleCount INT UNSIGNED NOT NULL,
    ScannedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    FOREIGN KEY (AccID) REFERENCES accounts(AccID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS vehicle_bottle_scan (
    VehicleScanID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    BatchID BIGINT UNSIGNED NOT NULL,
    BottleID BIGINT UNSIGNED NOT NULL,
    RefillID BIGINT UNSIGNED NULL,
    DPTID BIGINT UNSIGNED NULL,
    UNIQUE KEY uq_batch_bottle (BatchID, BottleID),
    FOREIGN KEY (BatchID) REFERENCES vehicle_scan_batch(BatchID),
    FOREIGN KEY (BottleID) REFERENCES bottles(BottleID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Preserve existing activity. Never invent loading or return scans for legacy data.
INSERT IGNORE INTO bottle_cycle (BottleID, CycleStatus, AccID, RefillID, ODTID, DPTID, UpdatedAt)
SELECT b.BottleID,
    CASE WHEN pm.MovementID IS NOT NULL AND (se.ScanDateTime IS NULL OR pm.MovementDateTime >= se.ScanDateTime)
         THEN IF(pm.MovementType = 'RETURN', 'RETURNED', 'DELIVERED')
         WHEN se.EventType = 'PICKUP_SCAN' THEN 'COLLECTED'
         WHEN se.EventType = 'DELIVERY_SCAN' THEN 'DELIVERED'
         ELSE 'READY' END,
    CASE WHEN pm.MovementID IS NOT NULL AND (se.ScanDateTime IS NULL OR pm.MovementDateTime >= se.ScanDateTime)
         THEN NULL WHEN se.EventType IN ('PICKUP_SCAN', 'DELIVERY_SCAN') THEN se.AccID ELSE NULL END,
    (SELECT MAX(r.RefillID) FROM refill r WHERE r.BottleID = b.BottleID),
    se.ODTID, se.DPTID,
    COALESCE(NULLIF(GREATEST(COALESCE(pm.MovementDateTime, '1000-01-01'), COALESCE(se.ScanDateTime, '1000-01-01')), '1000-01-01'), b.BottleRegDateTime)
FROM bottles b
LEFT JOIN bottle_scan_event se ON se.ScanEventID = (SELECT MAX(s.ScanEventID) FROM bottle_scan_event s WHERE s.BottleID = b.BottleID)
LEFT JOIN premise_bottle_movement pm ON pm.MovementID = (SELECT MAX(m.MovementID) FROM premise_bottle_movement m WHERE m.BottleID = b.BottleID)
WHERE se.ScanEventID IS NOT NULL OR pm.MovementID IS NOT NULL OR EXISTS (SELECT 1 FROM refill r WHERE r.BottleID = b.BottleID);

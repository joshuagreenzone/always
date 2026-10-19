-- Apply after 20261012_vehicle_scan_event_types.sql.
-- Existing events remain unclassified; only future scans can record a cycle jump.
ALTER TABLE bottle_scan_event
    ADD COLUMN IsCycleJump TINYINT(1) NULL DEFAULT NULL AFTER EventType,
    ADD COLUMN PreviousScanEventID BIGINT UNSIGNED NULL AFTER IsCycleJump,
    ADD COLUMN ExpectedPreviousEventType ENUM('REFILL_SCAN','DELIVERY_SCAN','PICKUP_SCAN','LOAD_SCAN','UNLOAD_SCAN') NULL AFTER PreviousScanEventID,
    ADD COLUMN JumpReason TEXT NULL AFTER ExpectedPreviousEventType,
    ADD KEY idx_scan_event_previous (PreviousScanEventID),
    ADD CONSTRAINT fk_scan_event_previous FOREIGN KEY (PreviousScanEventID)
        REFERENCES bottle_scan_event (ScanEventID),
    ADD CONSTRAINT chk_scan_event_jump_reason CHECK (
        (IsCycleJump IS NULL AND JumpReason IS NULL)
        OR (IsCycleJump = 0 AND JumpReason IS NULL)
        OR (IsCycleJump = 1 AND ExpectedPreviousEventType IS NOT NULL
            AND JumpReason IS NOT NULL AND CHAR_LENGTH(TRIM(JumpReason)) > 0)
    );

ALTER TABLE vehicle_scan_batch
    ADD TripDate DATE NULL,
    ADD TripNumber INT UNSIGNED NULL,
    ADD BatchCode VARCHAR(32) NULL,
    ADD RequestKey VARCHAR(64) NULL,
    ADD RequestHash CHAR(64) NULL,
    ADD SavedResult JSON NULL;

-- Legacy ScannedAt is a local wall-clock datetime; retain its recorded date.
UPDATE vehicle_scan_batch b JOIN (
    SELECT BatchID, DATE(ScannedAt) TripDate,
        ROW_NUMBER() OVER (PARTITION BY AccID, DATE(ScannedAt) ORDER BY ScannedAt, BatchID) TripNumber
    FROM vehicle_scan_batch WHERE Action = 'LOAD'
) numbered ON numbered.BatchID = b.BatchID
SET b.TripDate = numbered.TripDate, b.TripNumber = numbered.TripNumber,
    b.BatchCode = CONCAT(DATE_FORMAT(numbered.TripDate, '%m%d%y'), '-', numbered.TripNumber);

ALTER TABLE vehicle_scan_batch
    ADD UNIQUE KEY uq_rider_daily_trip (AccID, TripDate, TripNumber),
    ADD UNIQUE KEY uq_rider_batch_request (AccID, RequestKey);

ALTER TABLE vehicle_bottle_scan
    ADD SourceBatchID BIGINT UNSIGNED NULL,
    ADD IsCarryOver TINYINT(1) NOT NULL DEFAULT 0,
    ADD CONSTRAINT fk_carry_source_batch FOREIGN KEY (SourceBatchID) REFERENCES vehicle_scan_batch(BatchID);

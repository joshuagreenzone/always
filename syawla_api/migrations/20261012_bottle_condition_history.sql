-- Apply to the existing Syawla database before deploying the condition endpoints.
-- BottleCondition already exists on bottles (HEALTHY, MISSING, DAMAGED).
CREATE TABLE IF NOT EXISTS bottle_condition_history (
    ConditionHistoryID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    BottleID BIGINT UNSIGNED NOT NULL,
    AccID BIGINT UNSIGNED NOT NULL,
    PreviousCondition ENUM('HEALTHY', 'MISSING', 'DAMAGED') NOT NULL,
    NewCondition ENUM('HEALTHY', 'MISSING', 'DAMAGED') NOT NULL,
    Note VARCHAR(1000) NOT NULL,
    UpdatedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (ConditionHistoryID),
    KEY idx_condition_history_bottle (BottleID, ConditionHistoryID),
    CONSTRAINT fk_condition_history_bottle FOREIGN KEY (BottleID)
        REFERENCES bottles (BottleID) ON UPDATE CASCADE,
    CONSTRAINT fk_condition_history_account FOREIGN KEY (AccID)
        REFERENCES accounts (AccID) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

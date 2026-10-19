-- Independent dispenser inventory and custody history in the active `always` database.
CREATE TABLE IF NOT EXISTS dispensers (
    DispenserID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    DispenserNumber VARCHAR(64) NOT NULL,
    Brand VARCHAR(100) NULL,
    Model VARCHAR(100) NULL,
    DispenserAcquisition ENUM('BRAND_NEW','SECOND_HAND') NULL DEFAULT NULL,
    DispenserCost DECIMAL(12,2) NULL,
    DispenserPaymentStatus ENUM('FREE','PAID','UNPAID') NULL DEFAULT NULL,
    SerialNumber VARCHAR(100) NULL,
    PhysicalState ENUM('HEALTHY','DAMAGED','INOPERATIVE','MISSING') NOT NULL DEFAULT 'HEALTHY',
    LifecycleStatus ENUM('AVAILABLE','LOADED','DELIVERED','PICKED_UP') NOT NULL DEFAULT 'AVAILABLE',
    CurrentCustomerID BIGINT UNSIGNED NULL,
    CurrentAccID BIGINT UNSIGNED NULL,
    RegisteredAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    UpdatedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    UNIQUE KEY uq_dispenser_number (DispenserNumber),
    UNIQUE KEY uq_dispenser_serial (SerialNumber),
    KEY idx_dispenser_status (LifecycleStatus, PhysicalState),
    KEY idx_dispenser_customer (CurrentCustomerID),
    CONSTRAINT fk_dispenser_customer FOREIGN KEY (CurrentCustomerID) REFERENCES customers(CustomerID),
    CONSTRAINT fk_dispenser_rider FOREIGN KEY (CurrentAccID) REFERENCES accounts(AccID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dispenser_scan_event (
    ScanEventID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    DispenserID BIGINT UNSIGNED NOT NULL,
    AccID BIGINT UNSIGNED NOT NULL,
    EventType ENUM('LOAD_SCAN','DELIVERY_SCAN','PICKUP_SCAN','RETURN_SCAN') NOT NULL,
    CustomerID BIGINT UNSIGNED NULL,
    PreviousScanEventID BIGINT UNSIGNED NULL,
    ExpectedPreviousEventType ENUM('LOAD_SCAN','DELIVERY_SCAN','PICKUP_SCAN','RETURN_SCAN') NULL,
    IsCycleJump TINYINT(1) NOT NULL DEFAULT 0,
    JumpReason TEXT NULL,
    ScannedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    KEY idx_dispenser_scan_history (DispenserID, ScanEventID),
    KEY idx_dispenser_scan_customer (CustomerID),
    CONSTRAINT fk_dispenser_scan_dispenser FOREIGN KEY (DispenserID) REFERENCES dispensers(DispenserID),
    CONSTRAINT fk_dispenser_scan_actor FOREIGN KEY (AccID) REFERENCES accounts(AccID),
    CONSTRAINT fk_dispenser_scan_customer FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),
    CONSTRAINT fk_dispenser_scan_previous FOREIGN KEY (PreviousScanEventID) REFERENCES dispenser_scan_event(ScanEventID),
    CONSTRAINT chk_dispenser_scan_reason CHECK (
        (IsCycleJump = 0 AND JumpReason IS NULL) OR
        (IsCycleJump = 1 AND ExpectedPreviousEventType IS NOT NULL AND JumpReason IS NOT NULL AND CHAR_LENGTH(TRIM(JumpReason)) > 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dispenser_deployment (
    DeploymentID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    DispenserID BIGINT UNSIGNED NOT NULL,
    CustomerID BIGINT UNSIGNED NOT NULL,
    DeliveredScanEventID BIGINT UNSIGNED NULL,
    ClosedScanEventID BIGINT UNSIGNED NULL,
    DeliveredAt DATETIME(6) NULL,
    ClosedAt DATETIME(6) NULL,
    DeliveryWasInferred TINYINT(1) NOT NULL DEFAULT 0,
    CloseWasInferred TINYINT(1) NOT NULL DEFAULT 0,
    KEY idx_dispenser_deployment (DispenserID, DeliveredAt),
    KEY idx_customer_dispenser (CustomerID, DeliveredAt),
    CONSTRAINT fk_deployment_dispenser FOREIGN KEY (DispenserID) REFERENCES dispensers(DispenserID),
    CONSTRAINT fk_deployment_customer FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),
    CONSTRAINT fk_deployment_delivery_scan FOREIGN KEY (DeliveredScanEventID) REFERENCES dispenser_scan_event(ScanEventID),
    CONSTRAINT fk_deployment_close_scan FOREIGN KEY (ClosedScanEventID) REFERENCES dispenser_scan_event(ScanEventID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dispenser_state_history (
    StateHistoryID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    DispenserID BIGINT UNSIGNED NOT NULL,
    PreviousState ENUM('HEALTHY','DAMAGED','INOPERATIVE','MISSING') NOT NULL,
    NewState ENUM('HEALTHY','DAMAGED','INOPERATIVE','MISSING') NOT NULL,
    Note TEXT NOT NULL,
    RecordedByAccID BIGINT UNSIGNED NOT NULL,
    RecordedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    KEY idx_dispenser_state_history (DispenserID, StateHistoryID),
    CONSTRAINT fk_dispenser_state_dispenser FOREIGN KEY (DispenserID) REFERENCES dispensers(DispenserID),
    CONSTRAINT fk_dispenser_state_actor FOREIGN KEY (RecordedByAccID) REFERENCES accounts(AccID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS dispenser_maintenance (
    MaintenanceID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    DispenserID BIGINT UNSIGNED NOT NULL,
    CustomerID BIGINT UNSIGNED NULL,
    PerformedByAccID BIGINT UNSIGNED NULL,
    ExternalTechnicianName VARCHAR(150) NULL,
    RecordedByAccID BIGINT UNSIGNED NOT NULL,
    LocationType ENUM('CUSTOMER','STATION','OTHER') NOT NULL,
    LocationNote VARCHAR(255) NULL,
    MaintenanceNote TEXT NULL,
    WorkDone TEXT NOT NULL,
    PreviousState ENUM('HEALTHY','DAMAGED','INOPERATIVE','MISSING') NOT NULL,
    NewState ENUM('HEALTHY','DAMAGED','INOPERATIVE','MISSING') NOT NULL,
    PerformedAt DATETIME(6) NOT NULL,
    RecordedAt DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    VerificationMethod ENUM('SCAN','MANUAL') NOT NULL,
    VerificationNote TEXT NULL,
    KEY idx_dispenser_maintenance (DispenserID, PerformedAt),
    CONSTRAINT fk_dispenser_maintenance_dispenser FOREIGN KEY (DispenserID) REFERENCES dispensers(DispenserID),
    CONSTRAINT fk_dispenser_maintenance_customer FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),
    CONSTRAINT fk_dispenser_maintenance_worker FOREIGN KEY (PerformedByAccID) REFERENCES accounts(AccID),
    CONSTRAINT fk_dispenser_maintenance_actor FOREIGN KEY (RecordedByAccID) REFERENCES accounts(AccID),
    CONSTRAINT chk_dispenser_maintenance_technician CHECK (
        (PerformedByAccID IS NOT NULL AND ExternalTechnicianName IS NULL) OR
        (PerformedByAccID IS NULL AND ExternalTechnicianName IS NOT NULL AND CHAR_LENGTH(TRIM(ExternalTechnicianName)) > 0)
    ),
    CONSTRAINT chk_dispenser_maintenance_manual CHECK (
        VerificationMethod = 'SCAN' OR (VerificationNote IS NOT NULL AND CHAR_LENGTH(TRIM(VerificationNote)) > 0)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

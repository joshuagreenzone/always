-- Shared BottleID keeps all existing inventory, scan, delivery and payment links.
-- Presence here identifies a nonstandard QR; it is not a registered company QR.
-- Preserve the existing integer type/signedness and FK while allowing unknown
-- bottle type until a delivery assigns it from the remaining order quantities.
SET @qr_type_column = (SELECT COLUMN_TYPE FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bottles' AND COLUMN_NAME = 'BottleTypeID');
SET @qr_type_ddl = CONCAT('ALTER TABLE bottles MODIFY BottleTypeID ', @qr_type_column, ' NULL');
PREPARE qr_type_stmt FROM @qr_type_ddl;
EXECUTE qr_type_stmt;
DEALLOCATE PREPARE qr_type_stmt;

CREATE TABLE IF NOT EXISTS unregistered_qrs (
    UnregisteredQrID BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    BottleID INT NOT NULL,
    QrValue VARCHAR(200) NOT NULL,
    FirstSavedBy INT NULL,
    FirstSavedAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_unregistered_bottle (BottleID),
    UNIQUE KEY uq_unregistered_qr (QrValue)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO unregistered_qrs (BottleID, QrValue)
SELECT BottleID, BottleNumber FROM bottles
WHERE BottleNumber NOT REGEXP '^(A|RG|SG)-[0-9]{4}$'
ON DUPLICATE KEY UPDATE BottleID = VALUES(BottleID);

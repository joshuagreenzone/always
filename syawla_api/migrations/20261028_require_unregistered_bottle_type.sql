-- Assign real bottle types to any older untyped rows before applying this.
-- This deliberately fails if a NULL type remains rather than guessing a type.
SET @qr_type_column = (SELECT COLUMN_TYPE FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'bottles' AND COLUMN_NAME = 'BottleTypeID');
SET @qr_type_ddl = CONCAT('ALTER TABLE bottles MODIFY BottleTypeID ', @qr_type_column, ' NOT NULL');
PREPARE qr_type_stmt FROM @qr_type_ddl;
EXECUTE qr_type_stmt;
DEALLOCATE PREPARE qr_type_stmt;

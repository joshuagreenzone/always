-- Add a dedicated maintenance note for databases with dispenser lifecycle installed.
ALTER TABLE dispenser_maintenance
    ADD COLUMN MaintenanceNote TEXT NULL AFTER LocationNote;

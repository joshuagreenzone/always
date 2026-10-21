-- Existing registered bottles belong to the company.
-- Ownership is independent of physical state, custody, and scan cycle.
ALTER TABLE bottles
    ADD COLUMN IF NOT EXISTS BottleOwner ENUM('COMPANY', 'CUSTOMER') NOT NULL DEFAULT 'COMPANY' AFTER BottleAcquisition;

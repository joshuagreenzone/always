-- Record how a dispenser was acquired and the payment state of its acquisition cost.
-- Existing records remain NULL until their acquisition details are known.
ALTER TABLE dispensers
    ADD COLUMN DispenserAcquisition ENUM('BRAND_NEW','SECOND_HAND') NULL DEFAULT NULL AFTER Model,
    ADD COLUMN DispenserCost DECIMAL(12,2) NULL AFTER DispenserAcquisition,
    ADD COLUMN DispenserPaymentStatus ENUM('FREE','PAID','UNPAID') NULL DEFAULT NULL AFTER DispenserCost;

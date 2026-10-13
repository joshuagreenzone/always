-- Apply after 20261012_bottle_condition_history.sql.
-- Remember the latest refill at each state change to distinguish refills made
-- immediately after recovery, even when both timestamps fall in one second.
ALTER TABLE bottle_condition_history
    ADD COLUMN IF NOT EXISTS RefillIDAtUpdate BIGINT UNSIGNED NULL DEFAULT NULL;

-- Backfill existing history conservatively. Refills in the same second as an
-- old recovery are invalidated because their ordering cannot be established.
UPDATE bottle_condition_history h
SET RefillIDAtUpdate = COALESCE((
    SELECT MAX(r.RefillID) FROM refill r
    WHERE r.BottleID = h.BottleID AND r.RefillDateTime <= h.UpdatedAt
), 0)
WHERE h.RefillIDAtUpdate IS NULL;

-- Apply after 20261012_vehicle_bottle_cycle.sql, before deploying the API.
ALTER TABLE bottle_scan_event
    MODIFY EventType ENUM('REFILL_SCAN','DELIVERY_SCAN','PICKUP_SCAN','LOAD_SCAN','UNLOAD_SCAN') NOT NULL;

-- Preserve confirmed vehicle scans saved before bottle_scan_event integration.
-- Apply after 20261012_vehicle_scan_event_types.sql. Safe to rerun.
INSERT INTO bottle_scan_event
    (BottleID, AccID, EventType, RefillID, ODTID, DPTID, OrderID, DeliveryID, PickUpID, ScanDateTime)
SELECT v.BottleID, batch.AccID, IF(batch.Action = 'LOAD', 'LOAD_SCAN', 'UNLOAD_SCAN'),
    v.RefillID, odt.ODTID, v.DPTID, d.OrderID, p.DeliveryID, p.PickUpID, batch.ScannedAt
FROM vehicle_bottle_scan v
INNER JOIN vehicle_scan_batch batch ON batch.BatchID = v.BatchID
LEFT JOIN delivery_pickup_transaction dpt ON dpt.DPTID = v.DPTID
LEFT JOIN pickup p ON p.PickUpID = dpt.PickUpID
LEFT JOIN delivery d ON d.DeliveryID = p.DeliveryID
LEFT JOIN order_delivery_transaction odt ON odt.DeliveryID = p.DeliveryID AND odt.BottleID = v.BottleID
WHERE NOT EXISTS (
    SELECT 1 FROM bottle_scan_event e WHERE e.BottleID = v.BottleID
        AND e.AccID = batch.AccID AND e.EventType = IF(batch.Action = 'LOAD', 'LOAD_SCAN', 'UNLOAD_SCAN')
        AND e.ScanDateTime = CAST(batch.ScannedAt AS DATETIME)
)
ORDER BY batch.ScannedAt, v.VehicleScanID;

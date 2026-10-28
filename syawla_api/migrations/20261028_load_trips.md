# Rider loading trips

Apply `20261028_load_trips.sql` once to the local development database before
deploying the updated mobile API and Flutter app. Existing LOAD batches receive
per-rider daily numbers in recorded timestamp/ID order. RETURN batches are not
trips. No tables are created by this migration.

`vehicle_scan_batch` adds TripDate, TripNumber, BatchCode, RequestKey,
RequestHash and SavedResult. A displayed code such as `102826-2` means that
rider's second confirmed loading trip on October 28, 2026. Codes are scoped to
the rider; the numeric BatchID remains the internal primary key. New trip dates
use the database clock explicitly converted to Asia/Taipei (UTC+8).

`vehicle_bottle_scan` adds SourceBatchID and IsCarryOver. Carrying a bottle into
another trip inserts another membership row without deleting the original row,
changing the original batch count, creating a physical loading scan or changing
the bottle cycle. SourceBatchID points to the most recent known loading batch.
For legacy loaded bottles without a recorded batch, it is NULL; IsCarryOver
still records that the new membership was carried forward.

Opening Load for Delivery fetches a read-only loadContext snapshot. Undelivered
LOADED bottles belonging to that rider must be confirmed before scanning. Cancel
returns to the previous screen (or leaves loading blocked when used as a root
screen). Confirmation pre-populates the batch; carried bottles cannot be removed.
Newly scanned bottles can be removed normally. Saving only carried bottles is
allowed and counts as a new trip. Discarding the draft creates no trip. The total
batch size, including carried bottles, remains limited to 200.

The POST endpoint requires loadContext and a unique requestKey for LOAD.
Accounts are locked to serialize each rider's numbering. Current and scanned
bottles are locked in consistent order, then the snapshot is rechecked. A changed
previous trip, delivered bottle, transfer or changed scan requires reopening and
confirming the new snapshot. The endpoint uses READ COMMITTED so a transaction
waiting for a lock sees committed changes. Retrying the same request key and
payload returns its saved result; modifying a saved request is rejected.

Batch timestamp writes explicitly use CURRENT_TIMESTAMP at whole-second
precision, matching the existing physical scan writers. This avoids MySQL
rounding a datetime(6) batch time forward when inserted into datetime scan
history. A deterministic fractional-clock bottle-cycle regression covers this.

The inventory response includes loadContext, tripsToday and the latest 30 load
trips, including bottle membership and carry-over counts. The Flutter vehicle
tab shows trip codes and opens the recorded bottle list for each trip.

Validation commands:

```
php syawla_api/tests/load_trip_test.php
php syawla_api/tests/load_trip_concurrency_test.php
php syawla_api/tests/bottle_cycle_test.php --fractional-clock
php syawla_api/tests/bottle_condition_test.php
php syawla_api/tests/unregistered_qr_test.php --database
php syawla_api/tests/load_trip_http_test.php C:\laragon\www\always-system http://127.0.0.1:8081
flutter test test/vehicle_scan_screen_test.dart
flutter analyze
```

The main integration tests roll back fixtures. Concurrent and real HTTP tests
need short-lived committed fixtures for independent connections; finally blocks
remove only the accounts, bottles and dependent rows created by those tests.
Do not run fixture tests against production.

The active local API resides at
`C:\laragon\www\always-system\app\syawla_mobile_api`; its load-trip files and
supporting unregistered-QR type handling were synchronized with this repository.
Its existing refill supply-consumption code and database configuration were
preserved. A pre-migration database backup and pre-sync API file backups were
saved in the user's local Temp directory.

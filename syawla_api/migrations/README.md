# Bottle condition history

Apply `20261012_bottle_condition_history.sql` to the existing Syawla database
before deploying the new bottle-condition endpoints. It adds an audit table;
the existing `bottles.BottleCondition` enum stays `HEALTHY`, `MISSING`, `DAMAGED`.
Then apply `20261012_bottle_recovery_refill.sql` to record the refill cutoff
at each state change. In phpMyAdmin, select the database and import both files
in that order.

Each state change records the previous state, new state, required note,
staff account, and database-server date/time. Existing missing/damaged flags
remain in place; their previous update dates are unknown until a new change
is recorded. Updates and history inserts commit together.

Rider delivery/pickup and station-worker refill/registration scanners check
the bottle state before adding it to a temporary batch. Missing/damaged bottles
show a prompt to update the state or skip the bottle. Damaged bottles may be
picked up without changing their state; refill and delivery remain blocked.
Missing bottles require a state change before processing.
Restoring a missing/damaged bottle to healthy invalidates earlier refills:
it needs a new refill before delivery. Refill validation permits this replacement
refill when the last activity was at the station, while preserving custody rules.
Refill IDs distinguish ordering even when recovery/refill occur in one second.
State changes save immediately even if the user later discards the scan batch.
Existing delivery assignments and pickup ownership rules still apply.

Verification:

```text
flutter test --no-pub
php syawla_api/tests/bottle_condition_test.php
```

The PHP checks use a new fixture inside a rolled-back transaction. Test camera
scanning on a device with both staff roles: skip, blank note, successful update,
network failure, and a bottle whose state changes before batch confirmation.

## Rider vehicle cycle

Apply `20261012_vehicle_bottle_cycle.sql` after the condition/recovery migrations.
Then apply `20261012_vehicle_scan_event_types.sql` before deploying the API.
It extends `bottle_scan_event.EventType` with `LOAD_SCAN` (Load for Delivery)
and `UNLOAD_SCAN` (Return to Station). Each confirmed bottle writes one event,
including the rider and scan date/time, in the same transaction as its batch
and cycle update. Loading links to the refill; unloading links to the pickup
and delivery. Temporary scans and rejected batches do not write events.
Apply `20261012_backfill_vehicle_scan_events.sql` next to record any confirmed
vehicle batches saved before event integration. It preserves their original
rider and date/time and can be imported again without duplicating events.

Validation and inventories derive the current stage from the latest
`bottle_scan_event` by scan date/time, then event ID for ties:
`REFILL_SCAN` = ready, `LOAD_SCAN` = loaded, `DELIVERY_SCAN` = delivered,
`PICKUP_SCAN` = collected, `UNLOAD_SCAN` = returned. A missing or stale
`bottle_cycle` snapshot does not override scan history. Newer station-counter
release/return movements still determine custody; historical refill records
without scan events remain supported. Condition and recovery-refill checks
continue to apply independently.
Station return accepts a latest `PICKUP_SCAN` even without a cycle snapshot.
If an older event links only `PickUpID`, the API resolves that bottle's matching
pickup detail and still verifies the collecting rider. Unmatched pickup records,
another rider's bottles, and bottles already returned are rejected with specific
instructions. Damaged picked-up bottles remain eligible for station return.
It preserves existing refill, delivery, pickup, and premise movement activity.
It does not invent loading scans: existing ready stock must be loaded explicitly;
existing collected bottles must be scanned back into the station.

The cycle labels are **Ready for Loading**, **Loaded for Delivery**,
**Delivered to Customer**, **Collected from Customer**, and **Returned to Station**.
Condition (`HEALTHY`, `MISSING`, `DAMAGED`) is recorded separately from the cycle.
Unrefilled new bottles do not enter the five-stage cycle until their first refill.

Use the rider's **Load for Delivery** and **Return to Station** actions. Ownership
is per rider; no vehicle selection is required. Scans remain temporary until batch
confirmation. The server rechecks every bottle under row locks before saving
counts and audit records together. A failed batch saves no vehicle scans.

Delivery requires a bottle loaded by that rider. Station return requires a
confirmed pickup by that rider and accepts damaged bottles without changing
their condition. Customer collections cannot be refilled before station return.
After return, a healthy bottle must be refilled and loaded again for its next trip.
Recovery refills invalidate prior loading by resetting the bottle to ready stock.

Run `php syawla_api/tests/bottle_cycle_test.php` on a development database.
All test fixtures, load batches, and return batches are rolled back. For deployment,
update the Flutter client and API together so riders can perform the newly required
loading/return scans.

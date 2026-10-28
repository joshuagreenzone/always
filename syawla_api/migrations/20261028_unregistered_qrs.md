Apply `20261028_unregistered_qrs.sql`, then
`20261028_require_unregistered_bottle_type.sql` before deploying this change.

Nonstandard QR values are accepted by the existing workflow scanners and shown
in orange in pending batches. Scan previews and removed/discarded scans do not
write database rows. Confirmation inserts into `unregistered_qrs` in the same
transaction as the workflow; a failed batch rolls back both.

`unregistered_qrs.BottleID` links to a shared `bottles` record so existing scan,
refill, vehicle, delivery, pickup and payment relationships keep working. A QR in
this table remains unregistered even after it has workflow history. The migration
also classifies existing nonstandard bottle numbers.

The scanner asks for a bottle type when first scanning an external QR. The type
is kept in the pending batch and saved with the bottle only on confirmation.
Subsequent scans reuse that saved type. The API rejects new external QRs without
a valid selected type, and delivery matches the selected type to the order.
The follow-up migration restores NOT NULL on BottleTypeID; any older untyped rows
must first be assigned their actual types. Existing delivery association, bottle
condition, duplicate and skipped-step checks still apply.

Validation:

```
php syawla_api/tests/unregistered_qr_test.php
php syawla_api/tests/unregistered_qr_test.php --database
```

The second command requires a migrated development database with a rider fixture;
its changes are rolled back.

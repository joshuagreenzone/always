<?php
// Temporary tables shadow operational tables; fixtures disappear on disconnect.
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../services/payment_billing.php';

$db = (new Database())->connect();
$db->exec('CREATE TEMPORARY TABLE orders (OrderID INT, OrderStatus VARCHAR(20), Quantity INT, UnitPrice DECIMAL(12,2))');
$db->exec('CREATE TEMPORARY TABLE order_items (OrderItemID INT, OrderID INT, BottleTypeID INT, Quantity INT, UnitPrice DECIMAL(12,2), LineTotal DECIMAL(12,2), PromoID INT NULL, PromoBundleQuantity INT NULL, PromoBundlePrice DECIMAL(12,2) NULL)');
$db->exec('CREATE TEMPORARY TABLE bottles (BottleID INT, BottleTypeID INT)');
$db->exec('CREATE TEMPORARY TABLE order_delivery_transaction (ODTID INT, OrderID INT, OrderItemID INT NULL, BottleID INT)');
$db->exec('CREATE TEMPORARY TABLE bottle_scan_event (ODTID INT, EventType VARCHAR(30), ScanDateTime DATETIME)');
$db->exec("INSERT INTO orders VALUES (1, 'DELIVERED', 3, 15)");
$db->exec('INSERT INTO order_items VALUES (1, 1, 1, 3, 15, 35, 1, 3, 35)');
for ($id = 1; $id <= 3; $id++) {
    $db->exec("INSERT INTO bottles VALUES ($id, 1)");
    $db->exec("INSERT INTO order_delivery_transaction VALUES ($id, 1, 1, $id)");
    $db->exec("INSERT INTO bottle_scan_event VALUES ($id, 'DELIVERY_SCAN', NOW())");
}
function expectAmount(PDO $db, float $expected, string $case): void
{
    $actual = riderBillableAmount($db, 1);
    if ($actual !== $expected) throw new RuntimeException("$case: expected $expected, got $actual");
    echo "PASS: $case ($actual)\n";
}
expectAmount($db, 35.0, 'Full promo delivery bills 35 instead of 45');
$paid = 35.0;
if (round(riderBillableAmount($db, 1) - $paid, 2) !== 0.0) throw new RuntimeException('Full promo payment must settle the balance.');
if (round(riderBillableAmount($db, 1) - 20.0, 2) !== 15.0) throw new RuntimeException('Partial promo payment must retain 15 balance.');
$db->exec("UPDATE orders SET OrderStatus = 'INCOMPLETE'");
$db->exec('DELETE FROM bottle_scan_event WHERE ODTID = 3');
expectAmount($db, 30.0, 'Incomplete bundle charges two delivered bottles normally');
$db->exec('UPDATE order_items SET PromoID = NULL, PromoBundleQuantity = NULL, PromoBundlePrice = NULL, LineTotal = 45');
expectAmount($db, 30.0, 'Non-promo delivered billing is preserved');
$db->exec('DELETE FROM order_items');
expectAmount($db, 30.0, 'Legacy orders without items retain unit pricing');
echo "Promo payment billing regression checks passed; no operational rows changed.\n";

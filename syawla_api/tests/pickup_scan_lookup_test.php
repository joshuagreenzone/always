<?php
// Temporary tables shadow real application tables; no live records are changed.
require_once __DIR__ . '/../config/database.php';
$testDb = (new Database())->connect();
$schemas = [
    'accounts' => 'AccID INT',
    'account_roles' => 'AccID INT, Role VARCHAR(30)',
    'bottles' => 'BottleID INT, BottleNumber VARCHAR(50), BottleTypeID INT',
    'bottle_types' => 'BottleTypeID INT, BottleType VARCHAR(50)',
    'orders' => 'OrderID INT, CustomerID INT',
    'customers' => 'CustomerID INT, CustomerName VARCHAR(50)',
    'delivery' => 'DeliveryID INT, OrderID INT, AccID INT, DeliveryDateTime DATETIME, DeliveryStatus VARCHAR(30)',
    'order_items' => 'OrderItemID INT, OrderID INT, BottleTypeID INT',
    'order_delivery_transaction' => 'ODTID INT, DeliveryID INT, OrderID INT, OrderItemID INT, BottleID INT',
    'pickup' => 'PickUpID INT, DeliveryID INT, AccID INT',
    'delivery_pickup_transaction' => 'PickUpID INT, BottleID INT',
    'bottle_scan_event' => 'ODTID INT, EventType VARCHAR(30), IsCycleJump INT',
];
foreach ($schemas as $table => $columns) $testDb->exec("CREATE TEMPORARY TABLE `$table` ($columns)");
$testDb->exec("INSERT INTO accounts VALUES (3),(4);
    INSERT INTO account_roles VALUES (3,'RIDER'),(4,'RIDER');
    INSERT INTO bottle_types VALUES (1,'Round'),(2,'Slim');
    INSERT INTO bottles VALUES (1,'B-1',1),(2,'B-2',2),(3,'OTHER',1);
    INSERT INTO customers VALUES (1,'Sample customer');
    INSERT INTO orders VALUES (10,1),(42,1),(99,1);
    INSERT INTO delivery VALUES (10,10,3,'2026-10-01','DELIVERED'),(42,42,3,'2026-10-24','DELIVERED'),(99,99,4,'2026-10-24','DELIVERED');
    INSERT INTO order_items VALUES (1,10,1),(2,42,1),(3,42,2),(4,99,1);
    INSERT INTO order_delivery_transaction VALUES (1,10,10,1,1),(2,42,42,2,1),(3,42,42,3,2),(4,99,99,4,3)");
function lookupPickup(PDO $testDb, string $number): array
{
    $_GET = ['accId' => 3, 'bottleNumber' => $number];
    $source = file_get_contents(__DIR__ . '/../api/rider/get_pickup_orders.php');
    $source = str_replace(['<?php', "require_once '../../config/database.php';", '$database = new Database();', '$db = $database->connect();', 'exit;'],
        ['', '', '', '$db = $testDb;', 'return;'], $source);
    ob_start();
    eval($source);
    $result = json_decode(ob_get_clean(), true);
    if (empty($result['success'])) throw new RuntimeException('Pickup query failed.');
    return $result;
}
function checkPickup(bool $ok, string $message): void
{
    if (!$ok) throw new RuntimeException($message);
}
$match = lookupPickup($testDb, 'B-1');
checkPickup($match['matchedBottleNumber'] === 'B-1', 'Lookup capability marker missing.');
checkPickup(count($match['data']) === 1 && $match['data'][0]['OrderID'] === 42, 'Latest bottle delivery was not selected.');
checkPickup(count($match['data'][0]['BottleTypes']) === 2 && $match['data'][0]['RemainingBottleCount'] === 2, 'Full order details were lost.');
checkPickup(lookupPickup($testDb, 'UNKNOWN')['data'] === [], 'Unknown bottle matched an order.');
checkPickup(lookupPickup($testDb, 'OTHER')['data'] === [], 'Another rider delivery was exposed.');
$testDb->exec('INSERT INTO pickup VALUES (1,42,3); INSERT INTO delivery_pickup_transaction VALUES (1,1)');
checkPickup(lookupPickup($testDb, 'B-1')['data'] === [], 'Already picked up bottle was accepted.');
checkPickup(count(lookupPickup($testDb, 'B-2')['data']) === 1, 'Remaining bottle was not accepted.');
$testDb->exec("INSERT INTO bottle_scan_event VALUES (3,'UNLOAD_SCAN',1)");
checkPickup(lookupPickup($testDb, 'B-2')['data'] === [], 'Reasoned station return was not respected.');
echo "PASS: latest delivery, complete order details, rider ownership, unknown bottles, duplicate pickup, station return. No live records changed.\n";

<?php
// Dry run by default. --apply changes only settled promo orders' status.
$config = $argv[1] ?? __DIR__ . '/../config/database.php';
require_once $config;
require_once __DIR__ . '/../services/payment_billing.php';
$db = (new Database())->connect();
$apply = in_array('--apply', $argv, true);
$db->beginTransaction();
try {
    $rows = $db->query("SELECT o.OrderID, o.PaymentStatus,
        COALESCE((SELECT SUM(p.Amount) FROM order_payment_transaction p WHERE p.OrderID=o.OrderID),0) Paid
        FROM orders o WHERE o.OrderStatus IN ('DELIVERED','INCOMPLETE')
        AND o.PaymentStatus IN ('UNPAID','PARTIALLY_PAID')
        AND EXISTS (SELECT 1 FROM order_items i WHERE i.OrderID=o.OrderID AND i.PromoID IS NOT NULL)
        FOR UPDATE")->fetchAll(PDO::FETCH_ASSOC);
    $count = 0;
    foreach ($rows as $row) {
        $billable = riderBillableAmount($db, (int) $row['OrderID']);
        $paid = round((float) $row['Paid'], 2);
        if ($billable <= 0 || $paid !== $billable) continue;
        echo json_encode(['orderId' => (int) $row['OrderID'], 'previousStatus' => $row['PaymentStatus'],
            'billable' => $billable, 'paid' => $paid, 'newStatus' => 'PAID']) . PHP_EOL;
        if ($apply) $db->prepare("UPDATE orders SET PaymentStatus='PAID' WHERE OrderID=?")->execute([$row['OrderID']]);
        $count++;
    }
    if ($apply) $db->commit(); else $db->rollBack();
    echo ($apply ? 'Corrected' : 'Would correct') . " $count settled promo order status(es). No payment amounts changed.\n";
} catch (Throwable $e) {
    if ($db->inTransaction()) $db->rollBack();
    throw $e;
}

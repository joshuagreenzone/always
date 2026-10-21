<?php

declare(strict_types=1);

require_once __DIR__ . '/order_billing.php';

/** Use the same promo and incomplete-delivery amount as web finance. */
function riderBillableAmount(PDO $db, int $orderId): float
{
    $sql = 'SELECT ' . billableAmountSql('o') . ' AS Billable FROM orders o WHERE o.OrderID = ?';
    $statement = $db->prepare($sql);
    $statement->execute([$orderId]);
    $amount = $statement->fetchColumn();
    if ($amount === false) {
        throw new OutOfBoundsException('Order not found.');
    }
    return round((float) $amount, 2);
}

<?php

/*
|--------------------------------------------------------------------------
| ORDER BILLING HELPERS
|--------------------------------------------------------------------------
|
| Place at: services/order_billing.php
|
| ONE place that defines how much an order should actually be billed.
| Used by:
|   - api/stakeholder/get_customer_history.php
|   - api/stakeholder/get_customer_debt.php
|   - api/finance/pay_customer_debt.php
|   - services/finance_service.php
|
| BUSINESS RULE
| -------------
| Debt begins only after delivery is completed. DELIVERED and INCOMPLETE
| orders are billed only for bottles with a delivery scan. Pending and
| assigned orders have no receivable amount yet.
|
|   Example (order 36):
|     3 bottles ordered at 50.00  -> ordered amount   150.00
|     2 bottles delivered         -> delivered amount 100.00
|     customer already paid 150.00 -> overpaid by 50.00 (credit)
|
| A bottle counts as DELIVERED when its order_delivery_transaction row
| has a DELIVERY_SCAN in bottle_scan_event. This is the same rule that
| get_order_details.php uses (IsDelivered).
|
| Each function returns an SQL fragment. The fragment expects the
| orders table to be available under the alias you pass in
| (default "o") and uses these columns of it:
|   OrderID, OrderStatus, Quantity, UnitPrice
|
|--------------------------------------------------------------------------
*/


/*
 * Amount of everything that was ORDERED.
 *
 * Sum of the order's items. Falls back to the order's own
 * Quantity x UnitPrice for old orders that have no items.
 */
function orderedAmountSql(string $orderAlias = 'o'): string
{
    return "
        COALESCE(
            (
                SELECT SUM(COALESCE(oi_ord.LineTotal, oi_ord.Quantity * oi_ord.UnitPrice))
                FROM order_items oi_ord
                WHERE oi_ord.OrderID = {$orderAlias}.OrderID
            ),
            {$orderAlias}.Quantity * {$orderAlias}.UnitPrice,
            0
        )
    ";
}


/*
 * Amount of the bottles that were actually DELIVERED.
 *
 * Every delivered bottle is priced at the unit price of the order
 * item it belongs to:
 *   1. the order item linked on the delivery transaction, otherwise
 *   2. the order item of the same bottle type, otherwise
 *   3. the order's own unit price (old orders).
 *
 * $scanDateParam (optional) is a named PDO parameter such as
 * ':scan_date'. When given, only deliveries scanned on or before
 * that date count. It is used for month-end debt reports.
 * Promo-aware deliveredAmountSql also requires a matching parameter
 * with the suffix '_legacy' for the fallback branch (native PDO bindings).
 */
function legacyDeliveredAmountSql(
    string $orderAlias = 'o',
    ?string $scanDateParam = null
): string {

    $scanDateFilter = $scanDateParam !== null
        ? "AND s_del.ScanDateTime <= {$scanDateParam}"
        : '';

    return "
        COALESCE(
            (
                SELECT SUM(
                    COALESCE(
                        oi_del.UnitPrice,
                        (
                            SELECT oi_type.UnitPrice
                            FROM order_items oi_type
                            WHERE oi_type.OrderID = odt_del.OrderID
                              AND oi_type.BottleTypeID = b_del.BottleTypeID
                            ORDER BY oi_type.OrderItemID ASC
                            LIMIT 1
                        ),
                        {$orderAlias}.UnitPrice
                    )
                )
                FROM order_delivery_transaction odt_del

                INNER JOIN bottles b_del
                    ON b_del.BottleID = odt_del.BottleID

                LEFT JOIN order_items oi_del
                    ON oi_del.OrderItemID = odt_del.OrderItemID

                WHERE odt_del.OrderID = {$orderAlias}.OrderID
                  AND EXISTS (
                        SELECT 1
                        FROM bottle_scan_event s_del
                        WHERE s_del.ODTID = odt_del.ODTID
                          AND s_del.EventType = 'DELIVERY_SCAN'
                          {$scanDateFilter}
                  )
            ),
            0
        )
    ";
}

/** Price delivered quantities using the immutable promo bundle on each item. */
function deliveredAmountSql(string $orderAlias = 'o', ?string $scanDateParam = null): string
{
    $dateFilter = $scanDateParam ? "AND s.ScanDateTime <= {$scanDateParam}" : '';
    // The month-end report binds a separate legacy cutoff (native PDO placeholders).
    $legacyDate = $scanDateParam ? $scanDateParam . '_legacy' : null;
    $legacy = legacyDeliveredAmountSql($orderAlias, $legacyDate);
    return "COALESCE((
        SELECT SUM((
            SELECT CASE WHEN oi.PromoID IS NOT NULL AND oi.PromoBundleQuantity > 0
                THEN FLOOR(LEAST(COUNT(*), oi.Quantity) / oi.PromoBundleQuantity) * oi.PromoBundlePrice
                    + MOD(LEAST(COUNT(*), oi.Quantity), oi.PromoBundleQuantity) * oi.UnitPrice
                ELSE LEAST(COUNT(*), oi.Quantity) * oi.UnitPrice END
            FROM order_delivery_transaction dt
            INNER JOIN bottles b ON b.BottleID = dt.BottleID
            WHERE dt.OrderID = oi.OrderID
                AND (dt.OrderItemID = oi.OrderItemID OR (
                    dt.OrderItemID IS NULL AND b.BottleTypeID = oi.BottleTypeID
                    AND oi.OrderItemID = (SELECT MIN(first_item.OrderItemID) FROM order_items first_item
                        WHERE first_item.OrderID = oi.OrderID AND first_item.BottleTypeID = oi.BottleTypeID)
                ))
                AND EXISTS (SELECT 1 FROM bottle_scan_event s
                    WHERE s.ODTID = dt.ODTID AND s.EventType = 'DELIVERY_SCAN' {$dateFilter})
        )) FROM order_items oi WHERE oi.OrderID = {$orderAlias}.OrderID
    ), {$legacy}, 0)";
}


/*
 * Amount the customer should be billed for this order.
 *
 *   DELIVERED or INCOMPLETE order -> value of delivered bottles
 *   any other order             -> no debt yet
 *
 * $orderedSqlOverride remains in the signature for existing callers.
 */
function billableAmountSql(
    string $orderAlias = 'o',
    ?string $scanDateParam = null,
    ?string $orderedSqlOverride = null
): string {

    return "
        CASE
            WHEN UPPER(TRIM({$orderAlias}.OrderStatus)) IN ('DELIVERED', 'INCOMPLETE')
                THEN " . deliveredAmountSql($orderAlias, $scanDateParam) . "
            ELSE 0
        END
    ";
}

/** Prepaid undelivered orders reserve their payments; they are not customer credit. */
function creditBasisAmountSql(string $orderAlias = 'o'): string
{
    return "CASE WHEN UPPER(TRIM({$orderAlias}.OrderStatus)) IN ('DELIVERED', 'INCOMPLETE')
        THEN " . deliveredAmountSql($orderAlias) . "
        ELSE " . orderedAmountSql($orderAlias) . " END";
}


/*
 * Same billable amount, looked up from just an order ID
 * expression (for example "l.OrderID"). Useful inside queries
 * that do not have the orders table joined.
 */
function billableAmountForOrderIdSql(string $orderIdExpression): string
{
    return "
        (
            SELECT " . billableAmountSql('ob') . "
            FROM orders ob
            WHERE ob.OrderID = {$orderIdExpression}
            LIMIT 1
        )
    ";
}

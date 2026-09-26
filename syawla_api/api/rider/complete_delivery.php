<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

$db = null;

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * =========================================================
     * READ JSON REQUEST
     * =========================================================
     *
     * Expected:
     *
     * {
     *   "accId": 1,
     *   "orderId": 10,
     *   "deliveryId": 5,
     *   "bottles": [
     *     {
     *       "bottleNumber": "BTL001",
     *       "latitude": 13.12345678,
     *       "longitude": 121.12345678,
     *       "accuracy": 8.5
     *     }
     *   ]
     * }
     */

    $input = json_decode(
        file_get_contents('php://input'),
        true
    );

    if (!is_array($input)) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid JSON request.'
        ]);

        exit;
    }

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $orderId = isset($input['orderId'])
        ? (int) $input['orderId']
        : 0;

    $deliveryId = isset($input['deliveryId'])
        ? (int) $input['deliveryId']
        : 0;

    $bottles =
        isset($input['bottles']) &&
        is_array($input['bottles'])
            ? $input['bottles']
            : [];

    /*
     * =========================================================
     * BASIC VALIDATION
     * =========================================================
     */

    if (
        $accId <= 0 ||
        $orderId <= 0 ||
        $deliveryId <= 0
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Invalid delivery information.'
        ]);

        exit;
    }

    if (count($bottles) === 0) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'No bottles were provided.'
        ]);

        exit;
    }

    if (count($bottles) > 500) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' => 'Too many bottles were submitted.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * VERIFY RIDER + DELIVERY + ORDER
     * =========================================================
     *
     * NOTE:
     *
     * Bottle type is no longer read from orders.BottleTypeID.
     * The order may now contain multiple order_items.
     */

    $deliverySql = "
        SELECT
            d.DeliveryID,
            d.OrderID,
            d.AccID,
            d.DeliveryStatus,

            o.OrderStatus,
            o.PaymentStatus

        FROM delivery d

        INNER JOIN orders o
            ON d.OrderID = o.OrderID

        INNER JOIN accounts a
            ON d.AccID = a.AccID

        WHERE d.DeliveryID = :deliveryId
          AND d.OrderID = :orderId
          AND d.AccID = :accId
          AND a.AccType = 'RIDER'

        LIMIT 1
    ";

    $deliveryStmt = $db->prepare($deliverySql);

    $deliveryStmt->execute([
        ':deliveryId' => $deliveryId,
        ':orderId' => $orderId,
        ':accId' => $accId
    ]);

    $delivery = $deliveryStmt->fetch();

    if (!$delivery) {

        http_response_code(403);

        echo json_encode([
            'success' => false,
            'message' =>
                'This delivery is not assigned to this rider.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * CHECK DELIVERY STATUS
     * =========================================================
     */

    if (
        $delivery['DeliveryStatus'] ===
        'DELIVERED'
    ) {

        echo json_encode([
            'success' => true,
            'message' =>
                'Delivery has already been completed.',

            'data' => [
                'orderId' => $orderId,
                'deliveryId' => $deliveryId,
                'deliveryStatus' => 'DELIVERED',
                'orderStatus' => 'DELIVERED',
                'paymentStatus' =>
                    $delivery['PaymentStatus']
            ]
        ]);

        exit;
    }

    if (
        $delivery['DeliveryStatus'] ===
        'CANCELLED'
    ) {

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                'This delivery has been cancelled.'
        ]);

        exit;
    }

    /*
     * =========================================================
     * CHECK DUPLICATE BOTTLES IN REQUEST
     * =========================================================
     */

    $seenBottleNumbers = [];

    foreach ($bottles as $index => $item) {

        if (!is_array($item)) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Invalid bottle data at index ' .
                    $index . '.'
            ]);

            exit;
        }

        $number =
            isset($item['bottleNumber'])
                ? trim(
                    (string)
                    $item['bottleNumber']
                )
                : '';

        if ($number === '') {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'A bottle number is missing.'
            ]);

            exit;
        }

        $normalized =
            strtolower($number);

        if (
            isset(
                $seenBottleNumbers[
                    $normalized
                ]
            )
        ) {

            http_response_code(400);

            echo json_encode([
                'success' => false,
                'message' =>
                    'Duplicate bottle detected: ' .
                    $number
            ]);

            exit;
        }

        $seenBottleNumbers[
            $normalized
        ] = true;
    }

    /*
     * =========================================================
     * START TRANSACTION
     * =========================================================
     */

    $db->beginTransaction();

    try {

        /*
         * =====================================================
         * LOCK DELIVERY + ORDER
         * =====================================================
         */

        $lockDeliverySql = "
            SELECT
                d.DeliveryID,
                d.OrderID,
                d.AccID,
                d.DeliveryStatus,

                o.OrderStatus,
                o.PaymentStatus

            FROM delivery d

            INNER JOIN orders o
                ON d.OrderID = o.OrderID

            WHERE d.DeliveryID = :deliveryId
              AND d.OrderID = :orderId
              AND d.AccID = :accId

            FOR UPDATE
        ";

        $lockDeliveryStmt =
            $db->prepare(
                $lockDeliverySql
            );

        $lockDeliveryStmt->execute([
            ':deliveryId' =>
                $deliveryId,

            ':orderId' =>
                $orderId,

            ':accId' =>
                $accId
        ]);

        $lockedDelivery =
            $lockDeliveryStmt->fetch();

        if (!$lockedDelivery) {

            throw new Exception(
                'Delivery could not be locked.'
            );
        }

        if (
            $lockedDelivery[
                'DeliveryStatus'
            ] === 'DELIVERED'
        ) {

            throw new Exception(
                'This delivery has already been completed.'
            );
        }

        if (
            $lockedDelivery[
                'DeliveryStatus'
            ] === 'CANCELLED'
        ) {

            throw new Exception(
                'This delivery has been cancelled.'
            );
        }

        /*
         * =====================================================
         * LOAD + LOCK ORDER ITEMS
         * =====================================================
         *
         * This is now the source of truth for:
         *
         * - bottle types
         * - quantities
         * - order total quantity
         *
         * Example:
         *
         * Order 10
         *   Round Gallon  x 2
         *   Square Gallon x 1
         *   Wilkins       x 3
         *
         * Total required = 6 bottles
         */

        $orderItemsSql = "
            SELECT
                oi.OrderItemID,
                oi.OrderID,
                oi.BottleTypeID,
                oi.Quantity,
                oi.UnitPrice,
                bt.BottleType

            FROM order_items oi

            INNER JOIN bottle_types bt
                ON oi.BottleTypeID =
                   bt.BottleTypeID

            WHERE oi.OrderID =
                  :orderId

            ORDER BY
                oi.OrderItemID ASC

            FOR UPDATE
        ";

        $orderItemsStmt =
            $db->prepare(
                $orderItemsSql
            );

        $orderItemsStmt->execute([
            ':orderId' =>
                $orderId
        ]);

        $orderItems =
            $orderItemsStmt->fetchAll();

        if (!$orderItems) {

            throw new Exception(
                'This order does not contain any order items.'
            );
        }

        /*
         * =====================================================
         * CALCULATE REQUIRED TOTAL QUANTITY
         * =====================================================
         */

        $requiredCount = 0;

        /*
         * Remaining quantity for each order item.
         *
         * Example:
         *
         * [
         *   101 => 2,
         *   102 => 1,
         *   103 => 3
         * ]
         */

        $remainingItems = [];

        foreach ($orderItems as $orderItem) {

            $orderItemId =
                (int)
                $orderItem['OrderItemID'];

            $quantity =
                (int)
                $orderItem['Quantity'];

            if ($quantity <= 0) {

                throw new Exception(
                    'Order item ' .
                    $orderItemId .
                    ' has an invalid quantity.'
                );
            }

            $requiredCount +=
                $quantity;

            $remainingItems[
                $orderItemId
            ] = [
                'orderItemId' =>
                    $orderItemId,

                'bottleTypeId' =>
                    (int)
                    $orderItem['BottleTypeID'],

                'bottleType' =>
                    $orderItem['BottleType'],

                'quantity' =>
                    $quantity,

                'remaining' =>
                    $quantity,

                'unitPrice' =>
                    (float)
                    $orderItem['UnitPrice']
            ];
        }

        /*
         * =====================================================
         * EXACT TOTAL QUANTITY CHECK
         * =====================================================
         */

        $submittedCount =
            count($bottles);

        if (
            $submittedCount !==
            $requiredCount
        ) {

            throw new Exception(
                'The number of scanned bottles does not match the total order quantity. '
                . 'Required: ' .
                $requiredCount .
                ', submitted: ' .
                $submittedCount .
                '.'
            );
        }

        /*
         * =====================================================
         * CHECK EXISTING DELIVERY TRANSACTIONS
         * =====================================================
         *
         * The Flutter scanner stores scans only in memory.
         *
         * Therefore there should normally be no ODT records
         * before this endpoint is called.
         */

        $existingSql = "
            SELECT
                COUNT(*) AS ExistingCount

            FROM order_delivery_transaction

            WHERE OrderID = :orderId
              AND DeliveryID = :deliveryId
        ";

        $existingStmt =
            $db->prepare(
                $existingSql
            );

        $existingStmt->execute([
            ':orderId' =>
                $orderId,

            ':deliveryId' =>
                $deliveryId
        ]);

        $existingResult =
            $existingStmt->fetch();

        $existingCount =
            (int)
            $existingResult[
                'ExistingCount'
            ];

        if ($existingCount > 0) {

            throw new Exception(
                'This delivery already has saved bottle transactions. '
                . 'Please verify the delivery before continuing.'
            );
        }

        /*
         * =====================================================
         * PREPARE BOTTLE QUERY
         * =====================================================
         *
         * FOR UPDATE is important because the bottle is being
         * consumed from the available/refilled bottle pool.
         */

        $bottleSql = "
            SELECT
                b.BottleID,
                b.BottleNumber,
                b.BottleTypeID,
                bt.BottleType

            FROM bottles b

            INNER JOIN bottle_types bt
                ON b.BottleTypeID =
                   bt.BottleTypeID

            WHERE b.BottleNumber =
                  :bottleNumber

            LIMIT 1

            FOR UPDATE
        ";

        $bottleStmt =
            $db->prepare(
                $bottleSql
            );

        /*
         * =====================================================
         * BOTTLE CURRENTLY WITH ANOTHER CUSTOMER
         * =====================================================
         */

        $activeBottleSql = "
            SELECT
                odt.ODTID,
                odt.OrderID,
                odt.DeliveryID,
                d.DeliveryDateTime,
                d.DeliveryStatus

            FROM order_delivery_transaction odt

            INNER JOIN delivery d
                ON odt.DeliveryID =
                   d.DeliveryID

            WHERE odt.BottleID =
                  :bottleId

              AND d.DeliveryStatus =
                  'DELIVERED'

              AND NOT EXISTS (

                  SELECT 1

                  FROM delivery_pickup_transaction dpt

                  INNER JOIN pickup p
                      ON dpt.PickUpID =
                         p.PickUpID

                  WHERE dpt.BottleID =
                        odt.BottleID

                    AND p.DeliveryID =
                        odt.DeliveryID

                    AND p.PickUpDateTime >
                        d.DeliveryDateTime
              )

            ORDER BY
                d.DeliveryDateTime DESC

            LIMIT 1
        ";

        $activeBottleStmt =
            $db->prepare(
                $activeBottleSql
            );

        /*
         * =====================================================
         * BOTTLE ASSIGNED TO ANOTHER ACTIVE DELIVERY
         * =====================================================
         */

        $activeDeliverySql = "
            SELECT
                odt.ODTID,
                odt.OrderID,
                odt.DeliveryID,
                d.DeliveryStatus

            FROM order_delivery_transaction odt

            INNER JOIN delivery d
                ON odt.DeliveryID =
                   d.DeliveryID

            WHERE odt.BottleID =
                  :bottleId

              AND d.DeliveryStatus IN (
                  'ASSIGNED',
                  'OUT_FOR_DELIVERY'
              )

            LIMIT 1
        ";

        $activeDeliveryStmt =
            $db->prepare(
                $activeDeliverySql
            );

        /*
         * =====================================================
         * LATEST REFILL
         * =====================================================
         */

        $refillSql = "
            SELECT
                r.RefillID,
                r.RefillDateTime

            FROM refill r

            WHERE r.BottleID =
                  :bottleId

            ORDER BY
                r.RefillDateTime DESC,
                r.RefillID DESC

            LIMIT 1
        ";

        $refillStmt =
            $db->prepare(
                $refillSql
            );

        /*
         * =====================================================
         * LATEST PICKUP
         * =====================================================
         */

        $latestPickupSql = "
            SELECT
                p.PickUpID,
                p.PickUpDateTime

            FROM delivery_pickup_transaction dpt

            INNER JOIN pickup p
                ON dpt.PickUpID =
                   p.PickUpID

            WHERE dpt.BottleID =
                  :bottleId

            ORDER BY
                p.PickUpDateTime DESC,
                p.PickUpID DESC

            LIMIT 1
        ";

        $latestPickupStmt =
            $db->prepare(
                $latestPickupSql
            );

        /*
         * =====================================================
         * EXISTING EXACT ODT
         * =====================================================
         */

        $duplicateSql = "
            SELECT
                ODTID

            FROM order_delivery_transaction

            WHERE OrderID =
                  :orderId

              AND DeliveryID =
                  :deliveryId

              AND BottleID =
                  :bottleId

            LIMIT 1
        ";

        $duplicateStmt =
            $db->prepare(
                $duplicateSql
            );

        /*
         * =====================================================
         * PREPARE INSERT ODT
         * =====================================================
         *
         * IMPORTANT:
         *
         * OrderItemID is now saved so we know exactly which
         * order item this bottle fulfilled.
         */

        $insertOdtSql = "
            INSERT INTO order_delivery_transaction
            (
                OrderID,
                OrderItemID,
                DeliveryID,
                BottleID
            )
            VALUES
            (
                :orderId,
                :orderItemId,
                :deliveryId,
                :bottleId
            )
        ";

        $insertOdtStmt =
            $db->prepare(
                $insertOdtSql
            );

        /*
         * =====================================================
         * PREPARE INSERT SCAN EVENT
         * =====================================================
         */

        $insertScanSql = "
            INSERT INTO bottle_scan_event
            (
                BottleID,
                AccID,
                EventType,
                OrderID,
                DeliveryID,
                ODTID,
                ScanDateTime,
                Latitude,
                Longitude,
                LocationAccuracy
            )
            VALUES
            (
                :bottleId,
                :accId,
                'DELIVERY_SCAN',
                :orderId,
                :deliveryId,
                :odtId,
                CURRENT_TIMESTAMP,
                :latitude,
                :longitude,
                :locationAccuracy
            )
        ";

        $insertScanStmt =
            $db->prepare(
                $insertScanSql
            );

        /*
         * =====================================================
         * PROCESS ALL BOTTLES
         * =====================================================
         */

        $confirmedBottles = [];

        foreach ($bottles as $item) {

            $bottleNumber =
                trim(
                    (string)
                    $item['bottleNumber']
                );

            /*
             * -------------------------------------------------
             * GPS
             * -------------------------------------------------
             */

            $latitude =
                isset($item['latitude']) &&
                $item['latitude'] !== null &&
                $item['latitude'] !== ''
                    ? (float)
                        $item['latitude']
                    : null;

            $longitude =
                isset($item['longitude']) &&
                $item['longitude'] !== null &&
                $item['longitude'] !== ''
                    ? (float)
                        $item['longitude']
                    : null;

            $accuracy =
                isset($item['accuracy']) &&
                $item['accuracy'] !== null &&
                $item['accuracy'] !== ''
                    ? (float)
                        $item['accuracy']
                    : null;

            /*
             * -------------------------------------------------
             * FIND + LOCK BOTTLE
             * -------------------------------------------------
             */

            $bottleStmt->execute([
                ':bottleNumber' =>
                    $bottleNumber
            ]);

            $bottle =
                $bottleStmt->fetch();

            if (!$bottle) {

                throw new Exception(
                    'Bottle not found: ' .
                    $bottleNumber
                );
            }

            $bottleId =
                (int)
                $bottle['BottleID'];

            $bottleTypeId =
                (int)
                $bottle['BottleTypeID'];

            $bottleType =
                $bottle['BottleType'];

            /*
             * -------------------------------------------------
             * FIND ORDER ITEM FOR THIS BOTTLE TYPE
             * -------------------------------------------------
             *
             * We do NOT require Flutter to send OrderItemID.
             *
             * The server knows the bottle type from the scanned
             * bottle and matches it against the order items.
             *
             * Example:
             *
             * Order items:
             *   Round    x 2
             *   Square   x 1
             *
             * Scanned:
             *   Round
             *   Square
             *   Round
             *
             * The server automatically assigns:
             *   Round  -> first Round order item
             *   Square -> Square order item
             *   Round  -> remaining Round quantity
             */

            $matchedOrderItemId = null;

            foreach (
                $remainingItems
                as $orderItemId =>
                &$remainingItem
            ) {

                if (
                    $remainingItem[
                        'bottleTypeId'
                    ] === $bottleTypeId

                    &&

                    $remainingItem[
                        'remaining'
                    ] > 0
                ) {

                    $matchedOrderItemId =
                        (int)
                        $orderItemId;

                    $remainingItem[
                        'remaining'
                    ]--;

                    break;
                }
            }

            unset($remainingItem);

            if (
                $matchedOrderItemId === null
            ) {

                $expectedTypes = [];

                foreach (
                    $remainingItems
                    as $remainingItem
                ) {

                    if (
                        $remainingItem[
                            'remaining'
                        ] > 0
                    ) {

                        $expectedTypes[] =
                            $remainingItem[
                                'bottleType'
                            ]
                            .
                            ' x '
                            .
                            $remainingItem[
                                'remaining'
                            ];
                    }
                }

                $expectedText =
                    count($expectedTypes) > 0
                        ? implode(
                            ', ',
                            $expectedTypes
                        )
                        : 'none';

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' (' .
                    $bottleType .
                    ') cannot be matched to a remaining order item. '
                    .
                    'Remaining required types: ' .
                    $expectedText .
                    '.'
                );
            }

            /*
             * -------------------------------------------------
             * CHECK EXACT DELIVERY DUPLICATE
             * -------------------------------------------------
             */

            $duplicateStmt->execute([
                ':orderId' =>
                    $orderId,

                ':deliveryId' =>
                    $deliveryId,

                ':bottleId' =>
                    $bottleId
            ]);

            if ($duplicateStmt->fetch()) {

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' has already been scanned for this delivery.'
                );
            }

            /*
             * -------------------------------------------------
             * CHECK CUSTOMER OWNERSHIP
             * -------------------------------------------------
             */

            $activeBottleStmt->execute([
                ':bottleId' =>
                    $bottleId
            ]);

            if ($activeBottleStmt->fetch()) {

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' has already been delivered to another customer and has not been picked up yet.'
                );
            }

            /*
             * -------------------------------------------------
             * CHECK OTHER ACTIVE DELIVERY
             * -------------------------------------------------
             */

            $activeDeliveryStmt->execute([
                ':bottleId' =>
                    $bottleId
            ]);

            $activeDelivery =
                $activeDeliveryStmt->fetch();

            if ($activeDelivery) {

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' is already assigned to another active delivery.'
                );
            }

            /*
             * -------------------------------------------------
             * CHECK REFILL
             * -------------------------------------------------
             */

            $refillStmt->execute([
                ':bottleId' =>
                    $bottleId
            ]);

            $latestRefill =
                $refillStmt->fetch();

            if (!$latestRefill) {

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' has not been refilled yet.'
                );
            }

            /*
             * -------------------------------------------------
             * CHECK PICKUP
             * -------------------------------------------------
             */

            $latestPickupStmt->execute([
                ':bottleId' =>
                    $bottleId
            ]);

            $latestPickup =
                $latestPickupStmt->fetch();

            /*
             * If the latest pickup happened after the latest
             * refill, this bottle needs another refill.
             */

            if (
                $latestPickup &&
                strtotime(
                    $latestRefill[
                        'RefillDateTime'
                    ]
                ) <=
                strtotime(
                    $latestPickup[
                        'PickUpDateTime'
                    ]
                )
            ) {

                throw new Exception(
                    'Bottle ' .
                    $bottleNumber .
                    ' has been picked up but has not been refilled yet.'
                );
            }

            /*
             * =================================================
             * INSERT ODT
             * =================================================
             */

            $insertOdtStmt->execute([
                ':orderId' =>
                    $orderId,

                ':orderItemId' =>
                    $matchedOrderItemId,

                ':deliveryId' =>
                    $deliveryId,

                ':bottleId' =>
                    $bottleId
            ]);

            $odtId =
                (int)
                $db->lastInsertId();

            /*
             * =================================================
             * INSERT DELIVERY SCAN EVENT
             * =================================================
             */

            $insertScanStmt->execute([
                ':bottleId' =>
                    $bottleId,

                ':accId' =>
                    $accId,

                ':orderId' =>
                    $orderId,

                ':deliveryId' =>
                    $deliveryId,

                ':odtId' =>
                    $odtId,

                ':latitude' =>
                    $latitude,

                ':longitude' =>
                    $longitude,

                ':locationAccuracy' =>
                    $accuracy
            ]);

            $scanEventId =
                (int)
                $db->lastInsertId();

            /*
             * Keep information for response.
             */

            $confirmedBottles[] = [
                'bottleId' =>
                    $bottleId,

                'bottleNumber' =>
                    $bottle[
                        'BottleNumber'
                    ],

                'bottleTypeId' =>
                    $bottleTypeId,

                'bottleType' =>
                    $bottleType,

                'orderItemId' =>
                    $matchedOrderItemId,

                'odtId' =>
                    $odtId,

                'scanEventId' =>
                    $scanEventId
            ];
        }

        /*
         * =====================================================
         * VERIFY EVERY ORDER ITEM WAS FULFILLED
         * =====================================================
         *
         * This is more important than checking only the total
         * quantity.
         *
         * Example:
         *
         * Required:
         *   Round  x 2
         *   Square x 1
         *
         * Submitted:
         *   Round
         *   Round
         *   Round
         *
         * Total = 3
         *
         * The total quantity check alone would pass.
         *
         * The remaining-item check below correctly rejects it
         * because Square x 1 was never delivered.
         */

        $unfulfilledItems = [];

        foreach (
            $remainingItems
            as $remainingItem
        ) {

            if (
                $remainingItem[
                    'remaining'
                ] > 0
            ) {

                $unfulfilledItems[] = [
                    'orderItemId' =>
                        $remainingItem[
                            'orderItemId'
                        ],

                    'bottleTypeId' =>
                        $remainingItem[
                            'bottleTypeId'
                        ],

                    'bottleType' =>
                        $remainingItem[
                            'bottleType'
                        ],

                    'remaining' =>
                        $remainingItem[
                            'remaining'
                        ]
                ];
            }
        }

        if (
            count($unfulfilledItems) > 0
        ) {

            $details = [];

            foreach (
                $unfulfilledItems
                as $unfulfilled
            ) {

                $details[] =
                    $unfulfilled[
                        'bottleType'
                    ]
                    .
                    ' x '
                    .
                    $unfulfilled[
                        'remaining'
                    ];
            }

            throw new Exception(
                'Not all order items were fulfilled. '
                .
                'Remaining: '
                .
                implode(
                    ', ',
                    $details
                )
            );
        }

        /*
         * =====================================================
         * VERIFY FINAL BOTTLE COUNT
         * =====================================================
         */

        $finalCountSql = "
            SELECT
                COUNT(*) AS ScannedCount

            FROM order_delivery_transaction

            WHERE OrderID = :orderId
              AND DeliveryID = :deliveryId
        ";

        $finalCountStmt =
            $db->prepare(
                $finalCountSql
            );

        $finalCountStmt->execute([
            ':orderId' =>
                $orderId,

            ':deliveryId' =>
                $deliveryId
        ]);

        $finalCountResult =
            $finalCountStmt->fetch();

        $finalCount =
            (int)
            $finalCountResult[
                'ScannedCount'
            ];

        if (
            $finalCount !==
            $requiredCount
        ) {

            throw new Exception(
                'The final bottle count does not match the total order quantity.'
            );
        }

        /*
         * =====================================================
         * VERIFY ODT ORDER ITEM ASSIGNMENTS
         * =====================================================
         */

        $itemCountSql = "
            SELECT
                odt.OrderItemID,
                COUNT(*) AS ScannedCount

            FROM order_delivery_transaction odt

            WHERE odt.OrderID =
                  :orderId

              AND odt.DeliveryID =
                  :deliveryId

            GROUP BY
                odt.OrderItemID
        ";

        $itemCountStmt =
            $db->prepare(
                $itemCountSql
            );

        $itemCountStmt->execute([
            ':orderId' =>
                $orderId,

            ':deliveryId' =>
                $deliveryId
        ]);

        $itemCounts =
            $itemCountStmt->fetchAll();

        foreach ($itemCounts as $itemCount) {

            $itemId =
                (int)
                $itemCount[
                    'OrderItemID'
                ];

            $scanned =
                (int)
                $itemCount[
                    'ScannedCount'
                ];

            if (
                !isset(
                    $remainingItems[
                        $itemId
                    ]
                )
            ) {

                throw new Exception(
                    'A delivery transaction references an invalid order item.'
                );
            }

            $expected =
                (int)
                $remainingItems[
                    $itemId
                ][
                    'quantity'
                ];

            if (
                $scanned !==
                $expected
            ) {

                throw new Exception(
                    'Order item ' .
                    $itemId .
                    ' expected ' .
                    $expected .
                    ' bottle(s), but ' .
                    $scanned .
                    ' were scanned.'
                );
            }
        }

        /*
         * =====================================================
         * MARK DELIVERY DELIVERED
         * =====================================================
         */

        $updateDeliverySql = "
            UPDATE delivery

            SET
                DeliveryStatus = 'DELIVERED',
                DeliveryDateTime = NOW()

            WHERE DeliveryID =
                  :deliveryId

              AND OrderID =
                  :orderId

              AND AccID =
                  :accId
        ";

        $updateDeliveryStmt =
            $db->prepare(
                $updateDeliverySql
            );

        $updateDeliveryStmt->execute([
            ':deliveryId' =>
                $deliveryId,

            ':orderId' =>
                $orderId,

            ':accId' =>
                $accId
        ]);

        /*
         * IMPORTANT:
         *
         * Do NOT use rowCount() here.
         *
         * Verify the actual database value instead.
         */

        $verifyDeliverySql = "
            SELECT
                DeliveryID,
                DeliveryStatus

            FROM delivery

            WHERE DeliveryID =
                  :deliveryId

              AND OrderID =
                  :orderId

              AND AccID =
                  :accId

            LIMIT 1
        ";

        $verifyDeliveryStmt =
            $db->prepare(
                $verifyDeliverySql
            );

        $verifyDeliveryStmt->execute([
            ':deliveryId' =>
                $deliveryId,

            ':orderId' =>
                $orderId,

            ':accId' =>
                $accId
        ]);

        $verifiedDelivery =
            $verifyDeliveryStmt->fetch();

        if (!$verifiedDelivery) {

            throw new Exception(
                'Delivery could not be found after completion.'
            );
        }

        if (
            $verifiedDelivery[
                'DeliveryStatus'
            ] !== 'DELIVERED'
        ) {

            throw new Exception(
                'Unable to mark the delivery as completed.'
            );
        }

        /*
         * =====================================================
         * MARK ORDER DELIVERED
         * =====================================================
         */

        $updateOrderSql = "
            UPDATE orders

            SET
                OrderStatus = 'DELIVERED'

            WHERE OrderID =
                  :orderId
        ";

        $updateOrderStmt =
            $db->prepare(
                $updateOrderSql
            );

        $updateOrderStmt->execute([
            ':orderId' =>
                $orderId
        ]);

        /*
         * IMPORTANT:
         *
         * Do NOT use rowCount() here.
         */

        $verifyOrderSql = "
            SELECT
                OrderID,
                OrderStatus,
                PaymentStatus

            FROM orders

            WHERE OrderID =
                  :orderId

            LIMIT 1
        ";

        $verifyOrderStmt =
            $db->prepare(
                $verifyOrderSql
            );

        $verifyOrderStmt->execute([
            ':orderId' =>
                $orderId
        ]);

        $verifiedOrder =
            $verifyOrderStmt->fetch();

        if (!$verifiedOrder) {

            throw new Exception(
                'Order could not be found after delivery completion.'
            );
        }

        if (
            $verifiedOrder[
                'OrderStatus'
            ] !== 'DELIVERED'
        ) {

            throw new Exception(
                'Unable to mark the order as delivered.'
            );
        }

        /*
         * =====================================================
         * COMMIT
         * =====================================================
         */

        $db->commit();

        /*
         * =====================================================
         * SUCCESS RESPONSE
         * =====================================================
         */

        echo json_encode([
            'success' => true,

            'message' =>
                'Delivery completed successfully.',

            'data' => [

                'orderId' =>
                    $orderId,

                'deliveryId' =>
                    $deliveryId,

                'deliveryStatus' =>
                    'DELIVERED',

                'orderStatus' =>
                    'DELIVERED',

                'paymentStatus' =>
                    $verifiedOrder[
                        'PaymentStatus'
                    ],

                'requiredQuantity' =>
                    $requiredCount,

                'scannedQuantity' =>
                    $finalCount,

                'bottles' =>
                    $confirmedBottles
            ]
        ]);

        exit;

    } catch (Throwable $e) {

        /*
         * =====================================================
         * ROLLBACK
         * =====================================================
         *
         * If anything fails after beginTransaction(),
         * all ODT records and scan events created during this
         * request are rolled back.
         */

        if (
            $db->inTransaction()
        ) {

            $db->rollBack();
        }

        http_response_code(400);

        echo json_encode([
            'success' => false,
            'message' =>
                $e->getMessage()
        ]);

        exit;
    }

} catch (PDOException $e) {

    /*
     * =========================================================
     * DATABASE ERROR
     * =========================================================
     */

    if (
        $db !== null &&
        $db->inTransaction()
    ) {

        $db->rollBack();
    }

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' =>
            'Database error.'
    ]);

    exit;
}
?>

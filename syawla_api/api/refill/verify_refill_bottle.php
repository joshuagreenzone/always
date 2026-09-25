<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $bottleNumber = trim($_GET['bottleNumber'] ?? '');

    if ($bottleNumber === '') {
        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" => "Bottle number is required."
        ]);

        exit;
    }

    $database = new Database();
    $db = $database->connect();

    // ============================================================
    // FIND BOTTLE
    // ============================================================

    $bottleSql = "
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            b.BottleRegDateTime,
            bt.BottleType,
            bt.Price
        FROM bottles b
        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID
        WHERE b.BottleNumber = :bottleNumber
        LIMIT 1
    ";

    $bottleStmt = $db->prepare($bottleSql);

    $bottleStmt->execute([
        ':bottleNumber' => $bottleNumber
    ]);

    $bottle = $bottleStmt->fetch();

    if (!$bottle) {
        http_response_code(404);

        echo json_encode([
            "success" => false,
            "message" => "Invalid bottle. This bottle is not registered."
        ]);

        exit;
    }

    $bottleId = (int) $bottle['BottleID'];

    // ============================================================
    // FIND LATEST DELIVERY FOR THIS BOTTLE
    // ============================================================

    $deliverySql = "
        SELECT
            odt.ODTID,
            odt.OrderID,
            odt.DeliveryID,
            d.DeliveryStatus,
            d.DeliveryDateTime
        FROM order_delivery_transaction odt

        INNER JOIN delivery d
            ON odt.DeliveryID = d.DeliveryID

        WHERE odt.BottleID = :bottleId

        ORDER BY
            d.DeliveryDateTime DESC,
            odt.ODTID DESC

        LIMIT 1
    ";

    $deliveryStmt = $db->prepare($deliverySql);

    $deliveryStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestDelivery = $deliveryStmt->fetch();

    // ============================================================
    // FIND LATEST PICKUP FOR THIS BOTTLE
    // ============================================================

    $pickupSql = "
        SELECT
            dpt.DPTID,
            dpt.PickUpID,
            p.PickUpDateTime,
            p.DeliveryID
        FROM delivery_pickup_transaction dpt

        INNER JOIN pickup p
            ON dpt.PickUpID = p.PickUpID

        WHERE dpt.BottleID = :bottleId

        ORDER BY
            p.PickUpDateTime DESC,
            dpt.DPTID DESC

        LIMIT 1
    ";

    $pickupStmt = $db->prepare($pickupSql);

    $pickupStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestPickup = $pickupStmt->fetch();

    // ============================================================
    // CHECK CURRENT DELIVERY STATUS
    // ============================================================

    if ($latestDelivery) {

        $deliveryStatus = $latestDelivery['DeliveryStatus'];

        // --------------------------------------------------------
        // BOTTLE IS CURRENTLY OUT WITH RIDER
        // --------------------------------------------------------

        if (
            $deliveryStatus === 'ASSIGNED' ||
            $deliveryStatus === 'OUT_FOR_DELIVERY'
        ) {

            $hasBeenPickedUpAfterDelivery = false;

            if ($latestPickup) {
                $hasBeenPickedUpAfterDelivery =
                    strtotime($latestPickup['PickUpDateTime']) >
                    strtotime($latestDelivery['DeliveryDateTime']);
            }

            if (!$hasBeenPickedUpAfterDelivery) {

                http_response_code(409);

                echo json_encode([
                    "success" => false,
                    "message" =>
                        "Invalid bottle. This bottle is still out for delivery and cannot be refilled.",
                    "data" => [
                        "BottleID" => $bottleId,
                        "BottleNumber" => $bottle['BottleNumber'],
                        "DeliveryStatus" => $deliveryStatus
                    ]
                ]);

                exit;
            }
        }

        // --------------------------------------------------------
        // BOTTLE WAS DELIVERED BUT NOT PICKED UP
        // --------------------------------------------------------

        if ($deliveryStatus === 'DELIVERED') {

            $hasBeenPickedUpAfterDelivery = false;

            if ($latestPickup) {
                $hasBeenPickedUpAfterDelivery =
                    strtotime($latestPickup['PickUpDateTime']) >
                    strtotime($latestDelivery['DeliveryDateTime']);
            }

            if (!$hasBeenPickedUpAfterDelivery) {

                http_response_code(409);

                echo json_encode([
                    "success" => false,
                    "message" =>
                        "Invalid bottle. This bottle is still out and has already been delivered. It must be picked up before it can be refilled.",
                    "data" => [
                        "BottleID" => $bottleId,
                        "BottleNumber" => $bottle['BottleNumber'],
                        "DeliveryStatus" => $deliveryStatus,
                        "DeliveryID" => $latestDelivery['DeliveryID'],
                        "OrderID" => $latestDelivery['OrderID']
                    ]
                ]);

                exit;
            }
        }
    }

    // ============================================================
    // FIND LATEST REFILL
    // ============================================================

    $refillSql = "
        SELECT
            RefillID,
            RefillDateTime
        FROM refill

        WHERE BottleID = :bottleId

        ORDER BY
            RefillDateTime DESC,
            RefillID DESC

        LIMIT 1
    ";

    $refillStmt = $db->prepare($refillSql);

    $refillStmt->execute([
        ':bottleId' => $bottleId
    ]);

    $latestRefill = $refillStmt->fetch();

    // ============================================================
    // CHECK IF ALREADY REFILLED AFTER LATEST PICKUP
    // ============================================================

    if ($latestRefill && $latestPickup) {

        if (
            strtotime($latestRefill['RefillDateTime']) >=
            strtotime($latestPickup['PickUpDateTime'])
        ) {

            http_response_code(409);

            echo json_encode([
                "success" => false,
                "message" =>
                    "Invalid bottle. This bottle has already been refilled after its latest pickup and is ready for delivery.",
                "data" => [
                    "BottleID" => $bottleId,
                    "BottleNumber" => $bottle['BottleNumber'],
                    "RefillID" => $latestRefill['RefillID']
                ]
            ]);

            exit;
        }
    }

    // ============================================================
    // NO PICKUP
    // ============================================================

    if (!$latestPickup) {

        http_response_code(409);

        echo json_encode([
            "success" => false,
            "message" =>
                "Invalid bottle. This bottle has not been picked up yet and cannot be refilled."
        ]);

        exit;
    }

    // ============================================================
    // BOTTLE IS ELIGIBLE
    // ============================================================

    echo json_encode([
        "success" => true,
        "message" => "Bottle is eligible for refill.",
        "data" => [
            "BottleID" => (int) $bottle['BottleID'],
            "BottleNumber" => $bottle['BottleNumber'],
            "BottleTypeID" => (int) $bottle['BottleTypeID'],
            "BottleType" => $bottle['BottleType'],
            "Price" => (float) $bottle['Price'],
            "BottleRegDateTime" => $bottle['BottleRegDateTime']
        ]
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}
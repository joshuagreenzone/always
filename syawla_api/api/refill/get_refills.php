
<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * ---------------------------------------------------------
     * GET CURRENT REFILLED BOTTLES
     * ---------------------------------------------------------
     *
     * This endpoint returns ONLY bottles that are currently
     * refilled and ready for delivery.
     *
     * A bottle is considered available when:
     *
     * 1. It has a refill record.
     * 2. That refill is the bottle's latest refill.
     * 3. The bottle has NOT been scanned into a delivery
     *    after that refill.
     *
     * Old refill records remain in the database and will later
     * be available through the Refill History endpoint.
     */

    $sql = "
        SELECT
            r.RefillID,
            r.BottleID,
            r.RefillDateTime,

            b.BottleNumber,
            b.BottleTypeID,

            bt.BottleType,
            bt.Price

        FROM refill r

        INNER JOIN bottles b
            ON r.BottleID = b.BottleID

        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID

        /*
         * Only use the latest refill for each bottle.
         */
        WHERE r.RefillID = (
            SELECT r2.RefillID

            FROM refill r2

            WHERE r2.BottleID = r.BottleID

            ORDER BY
                r2.RefillDateTime DESC,
                r2.RefillID DESC

            LIMIT 1
        )

        /*
         * The bottle must NOT have been scanned into a
         * delivery after this refill.
         */
        AND NOT EXISTS (

            SELECT 1

            FROM order_delivery_transaction odt

            INNER JOIN delivery d
                ON odt.DeliveryID = d.DeliveryID

            WHERE odt.BottleID = r.BottleID

              AND d.DeliveryDateTime > r.RefillDateTime
        )

        ORDER BY
            r.RefillDateTime DESC,
            r.RefillID DESC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute();

    $refills = $stmt->fetchAll();

    echo json_encode([
        "success" => true,
        "data" => $refills
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}


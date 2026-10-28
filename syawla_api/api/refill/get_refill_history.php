
<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $database = new Database();
    $db = $database->connect();

    /*
     * ---------------------------------------------------------
     * GET REFILL HISTORY
     * ---------------------------------------------------------
     *
     * Returns ALL refill records.
     *
     * Refill records are historical records and are never
     * removed simply because the bottle was delivered or
     * picked up again.
     */

    $sql = "
        SELECT
            r.RefillID,
            r.BottleID,
            r.RefillDateTime,

            b.BottleNumber,
            b.BottleTypeID,

            COALESCE(bt.BottleType, 'Unregistered QR') AS BottleType,
            COALESCE(bt.Price, 0) AS Price

        FROM refill r

        INNER JOIN bottles b
            ON r.BottleID = b.BottleID

        LEFT JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID

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

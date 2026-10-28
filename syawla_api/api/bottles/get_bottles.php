<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $database = new Database();
    $db = $database->connect();

    $sql = "
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleOwner,
            b.BottleTypeID,
            COALESCE(bt.BottleType, 'Unregistered QR') AS BottleType,
            COALESCE(bt.Price, 0) AS Price,
            b.BottleRegDateTime
        FROM bottles b
        LEFT JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID
        ORDER BY b.BottleTypeID ASC, b.BottleNumber ASC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute();

    $bottles = $stmt->fetchAll();
    $counts = $db->query("SELECT COUNT(*) AS totalBottles,
        COALESCE(SUM(BottleOwner = 'COMPANY'), 0) AS companyBottles,
        COALESCE(SUM(BottleOwner = 'CUSTOMER'), 0) AS customerBottles FROM bottles")->fetch(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "data" => $bottles,
        "summary" => array_map('intval', $counts)
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}

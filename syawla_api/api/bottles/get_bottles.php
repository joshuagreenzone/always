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
            b.BottleTypeID,
            bt.BottleType,
            bt.Price,
            b.BottleRegDateTime
        FROM bottles b
        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID
        ORDER BY b.BottleTypeID ASC, b.BottleNumber ASC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute();

    $bottles = $stmt->fetchAll();

    echo json_encode([
        "success" => true,
        "data" => $bottles
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}
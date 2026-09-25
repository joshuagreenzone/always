<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $input = json_decode(file_get_contents("php://input"), true);

    $bottleNumber = trim($input['bottleNumber'] ?? '');

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

    /*
     * Find the bottle using the scanned QR value.
     */
    $sql = "
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            bt.BottleType,
            bt.Price
        FROM bottles b
        INNER JOIN bottle_types bt
            ON b.BottleTypeID = bt.BottleTypeID
        WHERE b.BottleNumber = :bottleNumber
        LIMIT 1
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':bottleNumber' => $bottleNumber
    ]);

    $bottle = $stmt->fetch();

    if (!$bottle) {

        http_response_code(404);

        echo json_encode([
            "success" => false,
            "message" => "Bottle not found."
        ]);

        exit;
    }

    /*
     * Prevent duplicate refill records for a bottle
     * that has already been refilled and has not yet
     * gone through the rest of the delivery cycle.
     *
     * For the initial refill implementation, any existing
     * refill record means the bottle is already refilled.
     */
    $checkSql = "
        SELECT
            RefillID,
            RefillDateTime
        FROM refill
        WHERE BottleID = :bottleId
        ORDER BY RefillDateTime DESC
        LIMIT 1
    ";

    $checkStmt = $db->prepare($checkSql);

    $checkStmt->execute([
        ':bottleId' => $bottle['BottleID']
    ]);

    $existingRefill = $checkStmt->fetch();

    if ($existingRefill) {

        http_response_code(409);

        echo json_encode([
            "success" => false,
            "message" => "This bottle has already been refilled.",
            "data" => [
                "BottleID" => $bottle['BottleID'],
                "BottleNumber" => $bottle['BottleNumber'],
                "BottleType" => $bottle['BottleType'],
                "RefillID" => $existingRefill['RefillID'],
                "RefillDateTime" => $existingRefill['RefillDateTime']
            ]
        ]);

        exit;
    }

    /*
     * Create the refill record.
     */
    $insertSql = "
        INSERT INTO refill
            (BottleID, RefillDateTime)
        VALUES
            (:bottleId, NOW())
    ";

    $insertStmt = $db->prepare($insertSql);

    $insertStmt->execute([
        ':bottleId' => $bottle['BottleID']
    ]);

    $refillId = $db->lastInsertId();

    echo json_encode([
        "success" => true,
        "message" => "Bottle refilled successfully.",
        "data" => [
            "RefillID" => $refillId,
            "BottleID" => $bottle['BottleID'],
            "BottleNumber" => $bottle['BottleNumber'],
            "BottleTypeID" => $bottle['BottleTypeID'],
            "BottleType" => $bottle['BottleType'],
            "Price" => $bottle['Price']
        ]
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}
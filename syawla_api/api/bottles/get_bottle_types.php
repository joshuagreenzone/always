<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

try {

    $database = new Database();
    $db = $database->connect();

    $stmt = $db->prepare("
        SELECT
            BottleTypeID,
            BottleType,
            BottlePrefix,
            Price
        FROM bottle_types
        ORDER BY BottleTypeID ASC
    ");

    $stmt->execute();

    $bottleTypes = [];

    while ($row = $stmt->fetch(PDO::FETCH_ASSOC)) {

        $bottleTypes[] = [
            'BottleTypeID' => (int) $row['BottleTypeID'],
            'BottleType' => $row['BottleType'],
            'BottlePrefix' => $row['BottlePrefix'],
            'Price' => (float) $row['Price'],
        ];
    }

    echo json_encode([
        'success' => true,
        'data' => [
            'bottleTypes' => $bottleTypes
        ]
    ]);

} catch (Throwable $e) {

    http_response_code(500);

    echo json_encode([
        'success' => false,
        'message' => 'Unable to load bottle types.'
    ]);
}
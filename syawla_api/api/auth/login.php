<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {

    $input = json_decode(file_get_contents("php://input"), true);

    $username = trim($input['username'] ?? '');
    $password = trim($input['password'] ?? '');

    if ($username === '' || $password === '') {

        http_response_code(400);

        echo json_encode([
            "success" => false,
            "message" => "Username and password are required."
        ]);

        exit;
    }

    $database = new Database();
    $db = $database->connect();

    $sql = "
        SELECT
            AccID,
            AccName,
            AccEmail,
            AccUsername,
            AccPassword,
            AccType
        FROM accounts
        WHERE AccUsername = :username
        LIMIT 1
    ";

    $stmt = $db->prepare($sql);

    $stmt->execute([
        ':username' => $username
    ]);

    $account = $stmt->fetch();

    if (!$account || $account['AccPassword'] !== $password) {

        http_response_code(401);

        echo json_encode([
            "success" => false,
            "message" => "Invalid username or password."
        ]);

        exit;
    }

    unset($account['AccPassword']);

    echo json_encode([
        "success" => true,
        "message" => "Login successful.",
        "data" => $account
    ]);

} catch (PDOException $e) {

    http_response_code(500);

    echo json_encode([
        "success" => false,
        "message" => "Database error."
    ]);
}
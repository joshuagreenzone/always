<?php

header('Content-Type: application/json');

require_once '../../config/database.php';

function respond(
    bool $success,
    string $message,
    int $statusCode = 200,
    array $data = []
): void {

    http_response_code($statusCode);

    echo json_encode([
        'success' => $success,
        'message' => $message,
        'data' => $data
    ]);

    exit;
}

try {

    $rawInput = file_get_contents('php://input');

    $input = json_decode($rawInput, true);

    if (!is_array($input)) {
        respond(
            false,
            'Invalid request data.',
            400
        );
    }

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $bottleTypeId = isset($input['bottleTypeId'])
        ? (int) $input['bottleTypeId']
        : 0;

    $bottleBrand = isset($input['bottleBrand'])
        ? trim((string) $input['bottleBrand'])
        : '';

    $bottleCondition = isset($input['bottleCondition'])
        ? trim((string) $input['bottleCondition'])
        : '';

    $bottleCost = isset($input['bottleCost'])
        ? (float) $input['bottleCost']
        : 0.00;

    $bottles = isset($input['bottles'])
        ? $input['bottles']
        : [];

    // ---------------------------------------------------------
    // Basic validation
    // ---------------------------------------------------------

    if ($accId <= 0) {
        respond(
            false,
            'Invalid account.',
            400
        );
    }

    if ($bottleTypeId <= 0) {
        respond(
            false,
            'Please select a bottle type.',
            400
        );
    }

    if (
        $bottleCondition !== 'BRAND_NEW' &&
        $bottleCondition !== 'SECOND_HAND'
    ) {
        respond(
            false,
            'Invalid bottle condition.',
            400
        );
    }

    if ($bottleCost < 0) {
        respond(
            false,
            'Bottle cost cannot be negative.',
            400
        );
    }

    if (!is_array($bottles)) {
        respond(
            false,
            'Invalid bottle list.',
            400
        );
    }

    if (count($bottles) === 0) {
        respond(
            false,
            'No bottles were selected for registration.',
            400
        );
    }

    if (count($bottles) > 500) {
        respond(
            false,
            'A maximum of 500 bottles may be registered at once.',
            400
        );
    }

    // ---------------------------------------------------------
    // Clean QR values.
    //
    // BottleNumber is intentionally treated as an opaque
    // string. Do NOT cast it to an integer.
    // ---------------------------------------------------------

    $cleanBottleNumbers = [];

    foreach ($bottles as $bottleNumber) {

        $bottleNumber =
            trim((string) $bottleNumber);

        if ($bottleNumber === '') {
            respond(
                false,
                'One of the scanned bottle QR values is empty.',
                400
            );
        }

        if (mb_strlen($bottleNumber) > 50) {
            respond(
                false,
                'A scanned QR value is too long.',
                400
            );
        }

        $cleanBottleNumbers[] =
            $bottleNumber;
    }

    // ---------------------------------------------------------
    // Detect duplicate QR scans in this request.
    // ---------------------------------------------------------

    $seen = [];

    foreach ($cleanBottleNumbers as $bottleNumber) {

        $normalized =
            mb_strtolower($bottleNumber);

        if (isset($seen[$normalized])) {

            respond(
                false,
                'The same bottle was scanned more than once in this batch.',
                409,
                [
                    'errorType' =>
                        'DUPLICATE_IN_BATCH',

                    'duplicateBottle' => [
                        'bottleNumber' =>
                            $bottleNumber
                    ]
                ]
            );
        }

        $seen[$normalized] = true;
    }

    // ---------------------------------------------------------
    // Database connection
    // ---------------------------------------------------------

    $database = new Database();

    $db = $database->connect();

    // ---------------------------------------------------------
    // Validate station worker account
    // ---------------------------------------------------------

    $accountStmt = $db->prepare("
        SELECT
            AccID,
            AccType
        FROM accounts
        WHERE AccID = :accId
        LIMIT 1
    ");

    $accountStmt->execute([
        ':accId' => $accId
    ]);

    $account =
        $accountStmt->fetch(PDO::FETCH_ASSOC);

    if (!$account) {
        respond(
            false,
            'Account not found.',
            403
        );
    }

    if ($account['AccType'] !== 'STATION_WORKER') {
        respond(
            false,
            'Only station workers may register bottles.',
            403
        );
    }

    // ---------------------------------------------------------
    // Validate selected bottle type
    // ---------------------------------------------------------

    $typeStmt = $db->prepare("
        SELECT
            BottleTypeID,
            BottleType,
            BottlePrefix,
            Price
        FROM bottle_types
        WHERE BottleTypeID = :bottleTypeId
        LIMIT 1
    ");

    $typeStmt->execute([
        ':bottleTypeId' =>
            $bottleTypeId
    ]);

    $requestedBottleType =
        $typeStmt->fetch(PDO::FETCH_ASSOC);

    if (!$requestedBottleType) {
        respond(
            false,
            'Selected bottle type does not exist.',
            400
        );
    }

    $requestedBottleTypeName =
        $requestedBottleType['BottleType'];

    // ---------------------------------------------------------
    // Server-side validation of EVERY QR.
    //
    // Nothing is inserted until all QR values have passed
    // validation.
    // ---------------------------------------------------------

    $existingBottleStmt = $db->prepare("
        SELECT
            b.BottleID,
            b.BottleNumber,
            b.BottleTypeID,
            bt.BottleType
        FROM bottles b
        INNER JOIN bottle_types bt
            ON bt.BottleTypeID = b.BottleTypeID
        WHERE b.BottleNumber = :bottleNumber
        LIMIT 1
    ");

    foreach ($cleanBottleNumbers as $bottleNumber) {

        $existingBottleStmt->execute([
            ':bottleNumber' =>
                $bottleNumber
        ]);

        $existingBottle =
            $existingBottleStmt
                ->fetch(PDO::FETCH_ASSOC);

        if (!$existingBottle) {
            continue;
        }

        $existingBottleType =
            $existingBottle['BottleType'];

        // -----------------------------------------------------
        // Already registered under WRONG bottle type
        // -----------------------------------------------------

        if (
            (int) $existingBottle['BottleTypeID'] !==
            $bottleTypeId
        ) {

            respond(
                false,
                'Bottle is already registered under a different bottle type.',
                409,
                [
                    'errorType' =>
                        'ALREADY_REGISTERED',

                    'bottle' => [
                        'bottleId' =>
                            (int) $existingBottle['BottleID'],

                        'bottleNumber' =>
                            $existingBottle['BottleNumber'],

                        'bottleTypeId' =>
                            (int) $existingBottle['BottleTypeID'],

                        'bottleType' =>
                            $existingBottleType
                    ],

                    'requestedBottleTypeId' =>
                        $bottleTypeId,

                    'requestedBottleType' =>
                        $requestedBottleTypeName
                ]
            );
        }

        // -----------------------------------------------------
        // Already registered under SAME bottle type
        // -----------------------------------------------------

        respond(
            false,
            'Bottle is already registered.',
            409,
            [
                'errorType' =>
                    'ALREADY_REGISTERED',

                'bottle' => [
                    'bottleId' =>
                        (int) $existingBottle['BottleID'],

                    'bottleNumber' =>
                        $existingBottle['BottleNumber'],

                    'bottleTypeId' =>
                        (int) $existingBottle['BottleTypeID'],

                    'bottleType' =>
                        $existingBottleType
                ],

                'requestedBottleTypeId' =>
                    $bottleTypeId,

                'requestedBottleType' =>
                    $requestedBottleTypeName
            ]
        );
    }

    // ---------------------------------------------------------
    // ALL bottles passed validation.
    //
    // Start ONE database transaction for the whole batch.
    // ---------------------------------------------------------

    $db->beginTransaction();

    try {

        $insertStmt = $db->prepare("
            INSERT INTO bottles
            (
                BottleNumber,
                BottleTypeID,
                BottleBrand,
                BottleCondition,
                BottleCost,
                BottleRegDateTime
            )
            VALUES
            (
                :bottleNumber,
                :bottleTypeId,
                :bottleBrand,
                :bottleCondition,
                :bottleCost,
                NOW()
            )
        ");

        $registeredBottles = [];

        foreach ($cleanBottleNumbers as $bottleNumber) {

            $insertStmt->execute([
                ':bottleNumber' =>
                    $bottleNumber,

                ':bottleTypeId' =>
                    $bottleTypeId,

                ':bottleBrand' =>
                    $bottleBrand !== ''
                        ? $bottleBrand
                        : null,

                ':bottleCondition' =>
                    $bottleCondition,

                ':bottleCost' =>
                    round($bottleCost, 2)
            ]);

            $bottleId =
                (int) $db->lastInsertId();

            $registeredBottles[] = [
                'bottleId' =>
                    $bottleId,

                'bottleNumber' =>
                    $bottleNumber,

                'bottleTypeId' =>
                    $bottleTypeId,

                'bottleType' =>
                    $requestedBottleTypeName,

                'bottleBrand' =>
                    $bottleBrand !== ''
                        ? $bottleBrand
                        : null,

                'bottleCondition' =>
                    $bottleCondition,

                'bottleCost' =>
                    round($bottleCost, 2),

                'bottleRegDateTime' =>
                    date('Y-m-d H:i:s')
            ];
        }

        // -----------------------------------------------------
        // Entire batch inserted successfully.
        // -----------------------------------------------------

        $db->commit();

        respond(
            true,
            'Bottles registered successfully.',
            201,
            [
                'count' =>
                    count($registeredBottles),

                'bottles' =>
                    $registeredBottles
            ]
        );

    } catch (PDOException $e) {

        if ($db->inTransaction()) {
            $db->rollBack();
        }

        // Database UNIQUE constraint is still the final
        // protection against duplicate BottleNumber values.
        if (
            isset($e->errorInfo[1]) &&
            (int) $e->errorInfo[1] === 1062
        ) {
            respond(
                false,
                'A bottle in this batch was registered by another request. '
                    . 'Please check the scanned bottles and try again.',
                409,
                [
                    'errorType' =>
                        'DATABASE_DUPLICATE'
                ]
            );
        }

        respond(
            false,
            'Database error while registering the bottle batch.',
            500
        );
    }

} catch (PDOException $e) {

    respond(
        false,
        'Database error while registering bottles.',
        500
    );

} catch (Throwable $e) {

    respond(
        false,
        'Unable to register bottles.',
        500
    );
}
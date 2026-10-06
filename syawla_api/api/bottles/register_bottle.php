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

    /*
     * ----------------------------------------------------------
     * READ JSON REQUEST
     * ----------------------------------------------------------
     */

    $rawInput = file_get_contents('php://input');

    $input = json_decode(
        $rawInput,
        true
    );

    if (!is_array($input)) {

        respond(
            false,
            'Invalid request data.',
            400
        );
    }


    /*
     * ----------------------------------------------------------
     * INPUTS
     * ----------------------------------------------------------
     */

    $accId = isset($input['accId'])
        ? (int) $input['accId']
        : 0;

    $bottleNumber = isset($input['bottleNumber'])
        ? trim((string) $input['bottleNumber'])
        : '';

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


    /*
     * ----------------------------------------------------------
     * BASIC VALIDATION
     * ----------------------------------------------------------
     */

    if ($accId <= 0) {

        respond(
            false,
            'Invalid account.',
            400
        );
    }

    if ($bottleNumber === '') {

        respond(
            false,
            'Bottle QR code is required.',
            400
        );
    }

    /*
     * bottles.BottleNumber is VARCHAR(50).
     */
    if (mb_strlen($bottleNumber) > 50) {

        respond(
            false,
            'The scanned QR value is too long.',
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


    /*
     * ----------------------------------------------------------
     * DATABASE
     * ----------------------------------------------------------
     */

    $database = new Database();
    $db = $database->connect();


    /*
     * ----------------------------------------------------------
     * VERIFY ACCOUNT
     *
     * Only station workers may register bottles.
     * ----------------------------------------------------------
     */

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

    $account = $accountStmt->fetch(PDO::FETCH_ASSOC);

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


    /*
     * ----------------------------------------------------------
     * CHECK DUPLICATE LEGACY QR
     *
     * The legacy QR value is stored directly as BottleNumber.
     *
     * We intentionally DO NOT inspect its prefix.
     * ----------------------------------------------------------
     */

    $duplicateStmt = $db->prepare("
        SELECT
            BottleID,
            BottleNumber,
            BottleTypeID
        FROM bottles
        WHERE BottleNumber = :bottleNumber
        LIMIT 1
    ");

    $duplicateStmt->execute([
        ':bottleNumber' => $bottleNumber
    ]);

    $existingBottle =
        $duplicateStmt->fetch(PDO::FETCH_ASSOC);

    if ($existingBottle) {

        respond(
            false,
            'This bottle is already registered.',
            409,
            [
                'requestedBottleNumber' => $bottleNumber,
                'existingBottle' => [
                    'bottleId' =>
                        (int) $existingBottle['BottleID'],

                    'bottleNumber' =>
                        $existingBottle['BottleNumber'],

                    'bottleTypeId' =>
                        (int) $existingBottle['BottleTypeID'],
                ]
            ]
        );
    }


    /*
     * ----------------------------------------------------------
     * VERIFY BOTTLE TYPE
     * ----------------------------------------------------------
     */

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
        ':bottleTypeId' => $bottleTypeId
    ]);

    $bottleType =
        $typeStmt->fetch(PDO::FETCH_ASSOC);

    if (!$bottleType) {

        respond(
            false,
            'Selected bottle type does not exist.',
            400
        );
    }


    /*
     * ----------------------------------------------------------
     * INSERT BOTTLE
     * ----------------------------------------------------------
     */

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


    /*
     * ----------------------------------------------------------
     * RETURN CREATED BOTTLE
     * ----------------------------------------------------------
     */

    respond(
        true,
        'Bottle registered successfully.',
        201,
        [
            'bottle' => [
                'bottleId' =>
                    $bottleId,

                'bottleNumber' =>
                    $bottleNumber,

                'bottleTypeId' =>
                    $bottleTypeId,

                'bottleType' =>
                    $bottleType['BottleType'],

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
            ]
        ]
    );

} catch (PDOException $e) {

    /*
     * Handle the UNIQUE BottleNumber constraint safely.
     */
    if ((int) $e->errorInfo[1] === 1062) {

        respond(
            false,
            'This bottle QR code is already registered.',
            409
        );
    }

    respond(
        false,
        'Database error while registering bottle.',
        500
    );

} catch (Throwable $e) {

    respond(
        false,
        'Unable to register bottle.',
        500
    );
}
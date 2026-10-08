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

        $bottleNumber = trim((string) $bottleNumber);

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

        $cleanBottleNumbers[] = $bottleNumber;
    }

    // ---------------------------------------------------------
    // Detect duplicate QR scans in this request.
    // ---------------------------------------------------------

    $seen = [];

    foreach ($cleanBottleNumbers as $bottleNumber) {

        $normalized = mb_strtolower($bottleNumber);

        if (isset($seen[$normalized])) {

            respond(
                false,
                'The same bottle was scanned more than once in this batch.',
                409,
                [
                    'errorType' => 'DUPLICATE_IN_BATCH',

                    'duplicateBottle' => [
                        'bottleNumber' => $bottleNumber
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
        ':bottleTypeId' => $bottleTypeId
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
    // Find bottles that already exist.
    //
    // IMPORTANT:
    //
    // Existing bottles are NOT errors anymore.
    //
    // They are placed into $existingBottles and skipped.
    // The rest of the batch continues normally.
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

    $existingBottles = [];

    $newBottleNumbers = [];

    foreach ($cleanBottleNumbers as $bottleNumber) {

        $existingBottleStmt->execute([
            ':bottleNumber' => $bottleNumber
        ]);

        $existingBottle =
            $existingBottleStmt->fetch(PDO::FETCH_ASSOC);

        if (!$existingBottle) {

            $newBottleNumbers[] = $bottleNumber;

            continue;
        }

        // -----------------------------------------------------
        // Already registered.
        //
        // Regardless of whether the existing bottle has the
        // same or different bottle type, skip it.
        // -----------------------------------------------------

        $existingBottles[] = $existingBottle['BottleNumber'];
    }

    // ---------------------------------------------------------
    // Register only NEW bottles.
    // ---------------------------------------------------------

    $registeredBottles = [];

    // Only start a transaction when there are actually
    // new bottles to insert.
    if (count($newBottleNumbers) > 0) {

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

            foreach ($newBottleNumbers as $bottleNumber) {

                $insertStmt->execute([
                    ':bottleNumber' => $bottleNumber,

                    ':bottleTypeId' => $bottleTypeId,

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

            $db->commit();

        } catch (PDOException $e) {

            if ($db->inTransaction()) {
                $db->rollBack();
            }

            // -------------------------------------------------
            // Database UNIQUE constraint is still the final
            // protection against duplicate BottleNumber values.
            //
            // This could happen if another request registered
            // the same QR after our initial check.
            // -------------------------------------------------

            if (
                isset($e->errorInfo[1]) &&
                (int) $e->errorInfo[1] === 1062
            ) {
                respond(
                    false,
                    'A bottle in this batch was registered by another request. '
                        . 'Please scan the bottle list again.',
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
    }

    // ---------------------------------------------------------
    // Build response message.
    // ---------------------------------------------------------

    $registeredCount =
        count($registeredBottles);

    $existingCount =
        count($existingBottles);

    if (
        $registeredCount > 0 &&
        $existingCount > 0
    ) {

        $message =
            $registeredCount
            . ' bottle(s) registered successfully. '
            . $existingCount
            . ' existing bottle(s) were skipped.';

    } elseif ($registeredCount > 0) {

        $message =
            $registeredCount
            . ' bottle(s) registered successfully.';

    } elseif ($existingCount > 0) {

        $message =
            'All scanned bottles were already registered. '
            . $existingCount
            . ' existing bottle(s) were skipped.';

    } else {

        $message =
            'No new bottles were registered.';
    }

    // ---------------------------------------------------------
    // Successful response.
    //
    // "bottles" = newly registered bottles
    //
    // "existingBottles" = bottles already in the database
    // and skipped from registration
    // ---------------------------------------------------------

    respond(
        true,
        $message,
        200,
        [
            'registeredCount' =>
                $registeredCount,

            'existingCount' =>
                $existingCount,

            'count' =>
                $registeredCount,

            'bottles' =>
                $registeredBottles,

            'existingBottles' =>
                $existingBottles
        ]
    );

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
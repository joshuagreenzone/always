
<?php

header("Content-Type: application/json");

require_once "../../config/database.php";

try {
    $database = new Database();
    $db = $database->connect();

    /*
     * =========================================================
     * GET READY-TO-DELIVER REFILLED BOTTLES
     * =========================================================
     *
     * Rules:
     * 1. The bottle must have a refill record.
     * 2. Only its latest refill is considered.
     * 3. If movement history exists, the latest movement
     *    must be RETURN and must not be after the refill.
     * 4. A bottle with no movement history can still qualify.
     * 5. A RELEASE must be resolved by a RETURN linked through
     *    RelatedMovementID.
     * 6. A delivery after the latest refill excludes the bottle.
     *
     * Historical refill records are never deleted.
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
            ON b.BottleID = r.BottleID

        INNER JOIN bottle_types bt
            ON bt.BottleTypeID = b.BottleTypeID

        /* Only the latest refill for each bottle. */
        WHERE NOT EXISTS (
            SELECT 1
            FROM refill r2
            WHERE r2.BottleID = r.BottleID
              AND (
                    r2.RefillDateTime > r.RefillDateTime
                    OR (
                        r2.RefillDateTime = r.RefillDateTime
                        AND r2.RefillID > r.RefillID
                    )
              )
        )

        /*
         * If movement history exists, the latest movement
         * must be RETURN and must occur no later than refill.
         * Bottles with no movement history are allowed.
         */
        AND (
            NOT EXISTS (
                SELECT 1
                FROM premise_bottle_movement pm
                WHERE pm.BottleID = r.BottleID
            )

            OR EXISTS (
                SELECT 1
                FROM premise_bottle_movement pm
                WHERE pm.BottleID = r.BottleID
                  AND pm.MovementType = 'RETURN'
                  AND pm.MovementDateTime <= r.RefillDateTime

                  AND NOT EXISTS (
                      SELECT 1
                      FROM premise_bottle_movement newer
                      WHERE newer.BottleID = pm.BottleID
                        AND (
                            newer.MovementDateTime >
                                pm.MovementDateTime
                            OR (
                                newer.MovementDateTime =
                                    pm.MovementDateTime
                                AND newer.MovementID > pm.MovementID
                            )
                        )
                  )
            )
        )

        /*
         * Exclude bottles with a RELEASE that has not been
         * resolved by a RETURN referencing that release.
         */
        AND NOT EXISTS (
            SELECT 1
            FROM premise_bottle_movement rel
            WHERE rel.BottleID = r.BottleID
              AND rel.MovementType = 'RELEASE'

              AND NOT EXISTS (
                  SELECT 1
                  FROM premise_bottle_movement ret
                  WHERE ret.MovementType = 'RETURN'
                    AND ret.RelatedMovementID = rel.MovementID
              )
        )

        /*
         * A delivery recorded after refill means the bottle
         * is no longer ready stock.
         */
        AND NOT EXISTS (
            SELECT 1
            FROM order_delivery_transaction odt

            INNER JOIN delivery d
                ON d.DeliveryID = odt.DeliveryID

            WHERE odt.BottleID = r.BottleID
              AND d.DeliveryDateTime > r.RefillDateTime
        )

        ORDER BY
            r.RefillDateTime DESC,
            r.RefillID DESC
    ";

    $stmt = $db->prepare($sql);
    $stmt->execute();

    $refills = $stmt->fetchAll(PDO::FETCH_ASSOC);

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
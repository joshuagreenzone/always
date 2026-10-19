<?php

function accountHasRole(PDO $db, int $accountId, string $role): bool
{
    $stmt = $db->prepare('SELECT 1 FROM accounts a WHERE a.AccID = ?
        AND EXISTS (
            SELECT 1 FROM account_roles ar WHERE ar.AccID = a.AccID AND ar.Role = ?
        )');
    $stmt->execute([$accountId, $role]);
    return (bool) $stmt->fetchColumn();
}

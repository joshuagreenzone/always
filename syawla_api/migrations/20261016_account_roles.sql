-- Backfill staff roles from the legacy AccType column before dropping it.
CREATE TABLE IF NOT EXISTS account_roles (
    AccID BIGINT UNSIGNED NOT NULL,
    Role ENUM('ADMIN', 'STATION_WORKER', 'RIDER') NOT NULL,
    PRIMARY KEY (AccID, Role),
    KEY idx_account_roles_role (Role, AccID),
    CONSTRAINT fk_account_roles_account FOREIGN KEY (AccID)
        REFERENCES accounts (AccID) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO account_roles (AccID, Role)
SELECT AccID, AccType FROM accounts;

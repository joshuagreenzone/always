-- Apply to always after 20261016_account_roles.sql and deployment of role-aware code.
-- Verify every account has an account_roles row before running this migration.
ALTER TABLE accounts DROP COLUMN AccType;

-- =====================================================================
-- Otigba MFB - Portfolio 2: OPTIONAL reset
-- Removes the four performance indexes so the "before" test can be repeated.
-- =====================================================================
DROP INDEX IF EXISTS idx_ledger_account_created;
DROP INDEX IF EXISTS idx_txn_failed_created;
DROP INDEX IF EXISTS idx_customers_lower_email;
DROP INDEX IF EXISTS idx_txn_created_covering;
ANALYZE;

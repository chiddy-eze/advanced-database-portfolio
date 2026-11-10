-- =====================================================================
-- Otigba MFB - Portfolio 2: indexes designed for the four queries
-- An index is like the index at the back of a textbook: the database
-- can jump to the right rows instead of reading every page (table scan).
-- =====================================================================

-- For Q1: PostgreSQL does NOT automatically index foreign-key columns.
-- Composite index = find one account's lines, already sorted by date.
CREATE INDEX IF NOT EXISTS idx_ledger_account_created
    ON ledger_entries (account_id, created_at DESC);

-- For Q2: PARTIAL index - only the ~3% of rows that are FAILED are indexed,
-- so the index is small and cheap to maintain.
CREATE INDEX IF NOT EXISTS idx_txn_failed_created
    ON transactions (created_at)
    WHERE status = 'FAILED';

-- For Q3: EXPRESSION index on lower(email). A normal index on email
-- cannot be used once the query wraps the column in lower().
CREATE INDEX IF NOT EXISTS idx_customers_lower_email
    ON customers (lower(email));

-- For Q4: COVERING index - date first (range filter), plus the columns the
-- query needs, so it can be answered from the index alone (Index Only Scan).
CREATE INDEX IF NOT EXISTS idx_txn_created_covering
    ON transactions (created_at)
    INCLUDE (txn_type, status, channel, amount);

-- Update statistics and the visibility map so the planner can use them
VACUUM ANALYZE ledger_entries;
VACUUM ANALYZE transactions;
VACUUM ANALYZE customers;

-- Evidence: list the indexes and their sizes
SELECT tablename, indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- =====================================================================
-- Otigba MFB - Portfolio 2: four business queries to benchmark
-- Run this file TWICE: once BEFORE 03_create_indexes.sql, once AFTER.
-- Highlight ONE block at a time and press F5 (or Fn+F5 / the play button).
-- EXPLAIN (ANALYZE, BUFFERS) really runs the query and reports:
--   * the plan the database chose (Seq Scan = read whole table,
--     Index Scan / Bitmap Index Scan = jump straight to matching rows)
--   * "Execution Time" in milliseconds  <-- record this number
-- Run each EXPLAIN 2-3 times and note the last figure (first run warms the cache).
-- =====================================================================


-- Q1. CUSTOMER SUPPORT: account statement - last 90 days for one account
--     (show the actual rows first, for the "query results" evidence)
SELECT le.created_at, t.reference, t.channel, le.entry_type, le.amount, le.balance_after
FROM ledger_entries le
JOIN accounts a     ON a.account_id = le.account_id
JOIN transactions t ON t.txn_id     = le.txn_id
WHERE a.account_number = '3020000123'
  AND le.created_at >= now() - INTERVAL '90 days'
ORDER BY le.created_at DESC;

EXPLAIN (ANALYZE, BUFFERS)
SELECT le.created_at, t.reference, t.channel, le.entry_type, le.amount, le.balance_after
FROM ledger_entries le
JOIN accounts a     ON a.account_id = le.account_id
JOIN transactions t ON t.txn_id     = le.txn_id
WHERE a.account_number = '3020000123'
  AND le.created_at >= now() - INTERVAL '90 days'
ORDER BY le.created_at DESC;


-- Q2. OPERATIONS: failed transfers in the last 7 days (to be reversed)
EXPLAIN (ANALYZE, BUFFERS)
SELECT txn_id, reference, amount, channel, created_at
FROM transactions
WHERE status = 'FAILED'
  AND created_at >= now() - INTERVAL '7 days'
ORDER BY created_at;


-- Q3. CUSTOMER SUPPORT: find a customer by e-mail, ignoring capital letters
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, first_name, last_name, phone, kyc_tier
FROM customers
WHERE lower(email) = lower('Cust12345@Example.com');


-- Q4. ANALYTICS: value of successful transfers per channel, last 30 days
EXPLAIN (ANALYZE, BUFFERS)
SELECT channel, count(*) AS transfers, sum(amount) AS total_value
FROM transactions
WHERE txn_type = 'TRANSFER'
  AND status   = 'SUCCESSFUL'
  AND created_at >= now() - INTERVAL '30 days'
GROUP BY channel
ORDER BY total_value DESC;

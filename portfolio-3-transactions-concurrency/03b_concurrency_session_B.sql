-- =====================================================================
-- Otigba MFB - Portfolio 3: CONCURRENCY - SESSION B (Query Tool tab 2)
-- Session B = a POS terminal charging account 3010000007 N10,000.
-- Only run a step when 03a_concurrency_session_A.sql tells you to.
-- =====================================================================

SELECT pg_backend_pid() AS session_b_pid;   -- step 0: note this number

-- ---------------- SCENARIO 1: lost update ----------------
BEGIN;                                                                     -- step 1.3
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 1.4 -> 60,000
UPDATE accounts SET balance = 50000 WHERE account_number = '3010000007';   -- step 1.5 (POS computed 60,000 - 10,000)
COMMIT;                                                                    -- step 1.6
--   >>> back to SESSION A, step 1.7 <<<


-- ---------------- SCENARIO 2: SELECT ... FOR UPDATE ----------------
BEGIN;                                                                     -- step 2.3
SELECT balance FROM accounts WHERE account_number = '3010000007' FOR UPDATE;  -- step 2.4
-- This tab now shows "Waiting for the query to complete..." - it is BLOCKED by A's lock.
--   >>> run step 2.5 in tab 3 (04_lock_monitor.sql), then go back to SESSION A, step 2.6 <<<
-- After A commits, this query finishes and shows 40,000 - the NEW balance  [SCREENSHOT: p3_17_s2_b_released_40000.png]
UPDATE accounts SET balance = balance - 10000 WHERE account_number = '3010000007';  -- step 2.8
COMMIT;                                                                    -- step 2.9
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 2.10 -> 30,000 CORRECT  [SCREENSHOT: p3_18_s2_final_30000.png]
--   >>> back to SESSION A, step 3.0 <<<


-- ---------------- SCENARIO 3: REPEATABLE READ ----------------
BEGIN ISOLATION LEVEL REPEATABLE READ;                                     -- step 3.3
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 3.4 -> 60,000
--   >>> back to SESSION A, steps 3.5 - 3.6 <<<
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 3.7 -> STILL 60,000  [SCREENSHOT: p3_19_s3_snapshot_60000.png]
-- (B keeps seeing its consistent snapshot, even though A has committed 40,000)
UPDATE accounts SET balance = balance - 10000 WHERE account_number = '3010000007';  -- step 3.8
-- Expected: ERROR: could not serialize access due to concurrent update   [SCREENSHOT: p3_20_s3_serialization_error.png]
ROLLBACK;                                                                  -- step 3.9
-- The application would now RETRY with fresh data:
UPDATE accounts SET balance = balance - 10000 WHERE account_number = '3010000007';  -- step 3.10 (retry, auto-commits)
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 3.11 -> 30,000 CORRECT  [SCREENSHOT: p3_21_s3_retry_30000.png]
--   >>> back to SESSION A, step 4.1 <<<


-- ---------------- SCENARIO 4 (optional): deadlock ----------------
BEGIN;                                                                              -- step 4.3
UPDATE accounts SET balance = balance - 1000 WHERE account_number = '3010000007';   -- step 4.4 (locks Ibrahim)
--   >>> back to SESSION A, step 4.5 <<<
UPDATE accounts SET balance = balance + 1000 WHERE account_number = '3010000005';   -- step 4.6 (waits for A -> DEADLOCK)
ROLLBACK;                                                                           -- step 4.8
--   >>> back to SESSION A, step 5.1 <<<

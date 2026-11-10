-- =====================================================================
-- Otigba MFB - Portfolio 3: CONCURRENCY - SESSION A (Query Tool tab 1)
-- Session A = the customer's MOBILE APP sending a N20,000 transfer.
-- Session B (tab 2) = a POS terminal charging the SAME account N10,000.
-- Account: 3010000007 (Ibrahim Sani), starting balance N60,000.
-- Correct final balance after both: 60,000 - 20,000 - 10,000 = N30,000.
--
-- Follow the step numbers IN ORDER, switching tabs as told.
-- Highlight ONE statement, press F5. Steps for B are in 03b_...sql.
-- =====================================================================

SELECT pg_backend_pid() AS session_a_pid;   -- step 0: note this number

-- =====================================================================
-- SCENARIO 1 - THE PROBLEM: "lost update" (default READ COMMITTED level)
-- The app reads the balance, calculates the new balance itself,
-- then writes the number back.
-- =====================================================================
UPDATE accounts SET balance = 60000 WHERE account_number = '3010000007';  -- step 1.0 (reset)
BEGIN;                                                                     -- step 1.1
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 1.2 -> 60,000
--   >>> now do steps 1.3 - 1.6 in SESSION B <<<
UPDATE accounts SET balance = 40000 WHERE account_number = '3010000007';   -- step 1.7 (app computed 60,000 - 20,000)
COMMIT;                                                                    -- step 1.8
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 1.9 -> 40,000 !!  [SCREENSHOT: p3_14_s1_lost_update_40000.png]
-- WRONG: should be 30,000. Session B's N10,000 POS debit was overwritten = LOST UPDATE.
-- The audit trigger caught it - two updates, both starting from 60,000:
SELECT audit_id, old_data->>'balance' AS old_balance, new_data->>'balance' AS new_balance, performed_at
FROM audit_log WHERE record_id = (SELECT account_id FROM accounts WHERE account_number = '3010000007')
ORDER BY audit_id DESC LIMIT 3;                                            -- step 1.10  [SCREENSHOT: p3_15_s1_audit_log.png]


-- =====================================================================
-- SCENARIO 2 - FIX 1: pessimistic locking with SELECT ... FOR UPDATE
-- =====================================================================
UPDATE accounts SET balance = 60000 WHERE account_number = '3010000007';  -- step 2.0 (reset)
BEGIN;                                                                     -- step 2.1
SELECT balance FROM accounts WHERE account_number = '3010000007' FOR UPDATE;  -- step 2.2 -> 60,000 (row now LOCKED)
--   >>> now do steps 2.3 - 2.4 in SESSION B (B will WAIT), then step 2.5 in tab 3 <<<
UPDATE accounts SET balance = balance - 20000 WHERE account_number = '3010000007';  -- step 2.6
COMMIT;                                                                    -- step 2.7  (B is released immediately)
--   >>> now do steps 2.8 - 2.10 in SESSION B <<<


-- =====================================================================
-- SCENARIO 3 - FIX 2: REPEATABLE READ isolation level
-- =====================================================================
UPDATE accounts SET balance = 60000 WHERE account_number = '3010000007';  -- step 3.0 (reset)
BEGIN ISOLATION LEVEL REPEATABLE READ;                                     -- step 3.1
SELECT balance FROM accounts WHERE account_number = '3010000007';          -- step 3.2 -> 60,000
--   >>> now do steps 3.3 - 3.4 in SESSION B <<<
UPDATE accounts SET balance = balance - 20000 WHERE account_number = '3010000007';  -- step 3.5
COMMIT;                                                                    -- step 3.6
--   >>> now do steps 3.7 - 3.11 in SESSION B <<<


-- =====================================================================
-- SCENARIO 4 (optional) - DEADLOCK
-- A moves N1,000 Emeka -> Ibrahim, B moves N1,000 Ibrahim -> Emeka,
-- each locking the accounts in the OPPOSITE order.
-- =====================================================================
BEGIN;                                                                              -- step 4.1
UPDATE accounts SET balance = balance - 1000 WHERE account_number = '3010000005';   -- step 4.2 (locks Emeka)
--   >>> now do steps 4.3 - 4.4 in SESSION B <<<
UPDATE accounts SET balance = balance + 1000 WHERE account_number = '3010000007';   -- step 4.5 (waits for B...)
--   >>> now do step 4.6 in SESSION B -> one of the two sessions gets "deadlock detected" <<<
ROLLBACK;                                                                           -- step 4.7  [SCREENSHOT: p3_22_s4_deadlock.png - whichever tab shows the error]


-- =====================================================================
-- FINAL RESET + AUDIT CHECK (run at the very end)
-- =====================================================================
UPDATE accounts SET balance = 60000 WHERE account_number = '3010000007';  -- step 5.1
SELECT * FROM v_balance_reconciliation;                                    -- step 5.2 -> 0 rows  [SCREENSHOT: p3_23_final_reconciliation.png]

-- step 5.3 (ONLY if 5.2 returned rows): an UPDATE was saved outside a
-- transaction (e.g. a missed BEGIN during Scenario 4). The audit view has
-- detected it  [SCREENSHOT: p3_23a_audit_mismatch_detected.png]
-- Repair: set each stored balance back to its ledger total, then re-run 5.2.
UPDATE accounts a
SET balance = r.ledger_balance
FROM v_balance_reconciliation r
WHERE a.account_number = r.account_number;

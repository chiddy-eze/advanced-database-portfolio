-- =====================================================================
-- Otigba MFB - Portfolio 3: COMMIT, ROLLBACK, atomicity and savepoints
-- Use ONE Query Tool tab. Highlight ONE statement at a time and press F5.
-- Screenshot each step marked [SCREENSHOT].
-- Accounts used (from Portfolio 1 seed data):
--   3010000001 Adaeze  | 3010000003 Tunde | 3010000004 Halima | 3010000006 Funmi
-- =====================================================================

-- Helper query - re-run whenever you want to see the four balances
SELECT account_number, balance FROM accounts
WHERE account_number IN ('3010000001','3010000003','3010000004','3010000006')
ORDER BY account_number;                                         -- [SCREENSHOT: p3_01_balances_before.png]


-- =====================================================================
-- DEMO 1: a successful transfer, made permanent with COMMIT
-- =====================================================================
BEGIN;                                                           -- step 1.1
SELECT fn_transfer('3010000001', '3010000003', 25000, 'P3-TRF-001');  -- step 1.2 (returns the new txn_id)
COMMIT;                                                          -- step 1.3
-- now re-run the helper query: Adaeze -25,000, Tunde +25,000     [SCREENSHOT: p3_02_demo1_after_commit.png]


-- =====================================================================
-- DEMO 2: atomicity - a transfer that fails leaves NO trace
-- Funmi has N15,000 and tries to send N20,000.
-- =====================================================================
SELECT fn_transfer('3010000006', '3010000004', 20000, 'P3-TRF-002');
-- Expected: ERROR: Insufficient funds: balance 15000.00, requested 20000   [SCREENSHOT: p3_03_demo2_insufficient_funds.png]

SELECT * FROM transactions WHERE reference = 'P3-TRF-002';
-- Expected: 0 rows - no half-finished transaction was saved     [SCREENSHOT: p3_04_demo2_no_rows_saved.png]


-- DEMO 2b: idempotency - re-sending the SAME transfer reference is rejected,
-- so a mobile-app retry can never debit the customer twice
SELECT fn_transfer('3010000001', '3010000003', 25000, 'P3-TRF-001');
-- Expected: ERROR: duplicate key value violates unique constraint "transactions_reference_key"  [SCREENSHOT: p3_05_demo2b_duplicate_reference.png]


-- =====================================================================
-- DEMO 3: ROLLBACK by choice - an operator forgets the WHERE clause
-- =====================================================================
BEGIN;                                                           -- step 3.1
UPDATE accounts SET status = 'FROZEN';                           -- step 3.2 (oops: ALL accounts!)
SELECT count(*) AS frozen_accounts FROM accounts WHERE status = 'FROZEN';  -- step 3.3 -> ~30,000  [SCREENSHOT: p3_06_demo3_frozen_before_rollback.png]
ROLLBACK;                                                        -- step 3.4 (undo everything since BEGIN)
SELECT count(*) AS frozen_accounts FROM accounts WHERE status = 'FROZEN';  -- step 3.5 -> 0        [SCREENSHOT: p3_07_demo3_after_rollback.png]


-- =====================================================================
-- DEMO 4: an error in the middle of a transaction undoes the earlier steps
-- Step 4.2 CREDITS Tunde, step 4.3 tries to DEBIT Funmi below zero.
-- =====================================================================
BEGIN;                                                                         -- step 4.1
UPDATE accounts SET balance = balance + 20000 WHERE account_number = '3010000003';  -- step 4.2 (works)
UPDATE accounts SET balance = balance - 20000 WHERE account_number = '3010000006';  -- step 4.3
-- Expected: ERROR ... violates check constraint "accounts_balance_check"     [SCREENSHOT: p3_08_demo4_check_error.png]
ROLLBACK;                                                                      -- step 4.4
-- (if pgAdmin already rolled back automatically, you may see
--  "WARNING: there is no transaction in progress" - that is fine)
-- Re-run the helper query: Tunde did NOT keep the N20,000 credit     [SCREENSHOT: p3_09_demo4_tunde_unchanged.png]


-- =====================================================================
-- DEMO 5: SAVEPOINT - keep the good part, undo only the failed part.
-- In PL/pgSQL an inner BEGIN ... EXCEPTION block is an automatic savepoint
-- (same as SAVEPOINT sp1; ... ROLLBACK TO SAVEPOINT sp1;).
-- Highlight the WHOLE DO block and run it once. Look at the Messages tab.
-- =====================================================================
DO $$
BEGIN
    PERFORM fn_transfer('3010000003', '3010000004', 5000, 'P3-TRF-003');      -- good
    RAISE NOTICE 'Transfer P3-TRF-003 (N5,000 Tunde -> Halima) done';
    BEGIN                                                                      -- savepoint
        PERFORM fn_transfer('3010000006', '3010000004', 999999, 'P3-TRF-004'); -- will fail
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'P3-TRF-004 failed (%) - rolled back to savepoint, P3-TRF-003 kept', SQLERRM;
    END;
END $$;
-- [SCREENSHOT: p3_10_demo5_savepoint_messages.png  (Messages tab)]
SELECT reference, amount, status FROM transactions
WHERE reference IN ('P3-TRF-003','P3-TRF-004');                 -- only P3-TRF-003 exists  [SCREENSHOT: p3_11_demo5_only_trf003.png]


-- =====================================================================
-- DEMO 6: reverse a completed transfer (customer dispute)
-- =====================================================================
SELECT fn_reverse_transfer(
         (SELECT txn_id FROM transactions WHERE reference = 'P3-TRF-001'),
         'P3-REV-001');

SELECT t.reference, t.txn_type, t.amount, t.status, o.reference AS reverses
FROM transactions t
LEFT JOIN transactions o ON o.txn_id = t.reversed_txn_id
WHERE t.reference IN ('P3-TRF-001','P3-REV-001');               -- original now REVERSED  [SCREENSHOT: p3_12_demo6_reversal.png]


-- =====================================================================
-- DEMO 7: audit - every stored balance still equals its ledger total
-- =====================================================================
SELECT * FROM v_balance_reconciliation;                          -- Expected: 0 rows        [SCREENSHOT: p3_13_demo7_reconciliation.png]

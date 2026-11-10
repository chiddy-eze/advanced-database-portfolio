-- =====================================================================
-- Otigba MFB - Portfolio 3: safe money-movement functions
-- Run the WHOLE file once (F5). It only creates functions.
-- A function runs inside ONE transaction: if any check fails, RAISE
-- EXCEPTION undoes everything it did (atomicity - the "A" in ACID).
-- =====================================================================

-- ---------------------------------------------------------------------
-- fn_transfer: move money from one account to another
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_transfer(
    p_from      CHAR(10),
    p_to        CHAR(10),
    p_amount    NUMERIC,
    p_reference VARCHAR,
    p_channel   VARCHAR DEFAULT 'MOBILE'
) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_from  accounts%ROWTYPE;
    v_to    accounts%ROWTYPE;
    v_limit NUMERIC;
    v_spent NUMERIC;
    v_txn   BIGINT;
BEGIN
    IF p_from = p_to THEN
        RAISE EXCEPTION 'Cannot transfer to the same account';
    END IF;

    -- CONCURRENCY CONTROL: lock BOTH account rows before reading balances.
    -- Locking in a fixed order (lowest account number first) means two
    -- opposite transfers (A->B and B->A) can never deadlock each other.
    PERFORM 1 FROM accounts
    WHERE account_number IN (p_from, p_to)
    ORDER BY account_number
    FOR UPDATE;

    SELECT * INTO v_from FROM accounts WHERE account_number = p_from;
    SELECT * INTO v_to   FROM accounts WHERE account_number = p_to;

    IF v_from.account_id IS NULL OR v_to.account_id IS NULL THEN
        RAISE EXCEPTION 'Account not found';
    END IF;
    IF v_from.status <> 'ACTIVE' OR v_to.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Both accounts must be ACTIVE';
    END IF;
    IF v_from.balance < p_amount THEN
        RAISE EXCEPTION 'Insufficient funds: balance %, requested %', v_from.balance, p_amount;
    END IF;

    -- Business rule: daily debit limit depends on the account type
    SELECT daily_debit_limit INTO v_limit
    FROM account_types WHERE account_type_code = v_from.account_type_code;

    SELECT COALESCE(SUM(amount), 0) INTO v_spent
    FROM ledger_entries
    WHERE account_id = v_from.account_id AND entry_type = 'DEBIT'
      AND created_at >= date_trunc('day', now());

    IF v_spent + p_amount > v_limit THEN
        RAISE EXCEPTION 'Daily limit of % exceeded (already spent % today)', v_limit, v_spent;
    END IF;

    -- 1 transaction row + 2 balance updates + 2 ledger lines = one unit of work
    INSERT INTO transactions (reference, txn_type, amount, channel, status, narration)
    VALUES (p_reference, 'TRANSFER', p_amount, p_channel, 'SUCCESSFUL', 'Transfer to ' || p_to)
    RETURNING txn_id INTO v_txn;

    UPDATE accounts SET balance = balance - p_amount WHERE account_id = v_from.account_id;
    UPDATE accounts SET balance = balance + p_amount WHERE account_id = v_to.account_id;

    INSERT INTO ledger_entries (txn_id, account_id, entry_type, amount, balance_after) VALUES
        (v_txn, v_from.account_id, 'DEBIT',  p_amount, v_from.balance - p_amount),
        (v_txn, v_to.account_id,   'CREDIT', p_amount, v_to.balance   + p_amount);

    RETURN v_txn;
END;
$$;

-- ---------------------------------------------------------------------
-- fn_reverse_transfer: undo a completed transfer (e.g. customer dispute)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reverse_transfer(p_txn_id BIGINT, p_reference VARCHAR)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_orig   transactions%ROWTYPE;
    v_debit  ledger_entries%ROWTYPE;   -- leg that sent the money
    v_credit ledger_entries%ROWTYPE;   -- leg that received it
    v_payer_bal NUMERIC;
    v_payee_bal NUMERIC;
    v_new    BIGINT;
BEGIN
    -- Lock the original transaction so it cannot be reversed twice at once
    SELECT * INTO v_orig FROM transactions WHERE txn_id = p_txn_id FOR UPDATE;

    IF v_orig.txn_id IS NULL OR v_orig.txn_type <> 'TRANSFER' OR v_orig.status <> 'SUCCESSFUL' THEN
        RAISE EXCEPTION 'Transaction % cannot be reversed (missing, not a transfer, or not SUCCESSFUL)', p_txn_id;
    END IF;

    SELECT * INTO v_debit  FROM ledger_entries WHERE txn_id = p_txn_id AND entry_type = 'DEBIT';
    SELECT * INTO v_credit FROM ledger_entries WHERE txn_id = p_txn_id AND entry_type = 'CREDIT';

    -- Lock both accounts in a fixed order (same deadlock-avoidance rule)
    PERFORM 1 FROM accounts
    WHERE account_id IN (v_debit.account_id, v_credit.account_id)
    ORDER BY account_id
    FOR UPDATE;

    -- The receiver must still have the money (CHECK balance >= 0 also guards this)
    UPDATE accounts SET balance = balance - v_orig.amount
    WHERE account_id = v_credit.account_id RETURNING balance INTO v_payee_bal;
    UPDATE accounts SET balance = balance + v_orig.amount
    WHERE account_id = v_debit.account_id  RETURNING balance INTO v_payer_bal;

    INSERT INTO transactions (reference, txn_type, amount, channel, status, narration, reversed_txn_id)
    VALUES (p_reference, 'REVERSAL', v_orig.amount, 'BRANCH', 'SUCCESSFUL',
            'Reversal of ' || v_orig.reference, v_orig.txn_id)
    RETURNING txn_id INTO v_new;

    INSERT INTO ledger_entries (txn_id, account_id, entry_type, amount, balance_after) VALUES
        (v_new, v_credit.account_id, 'DEBIT',  v_orig.amount, v_payee_bal),
        (v_new, v_debit.account_id,  'CREDIT', v_orig.amount, v_payer_bal);

    UPDATE transactions SET status = 'REVERSED' WHERE txn_id = v_orig.txn_id;
    RETURN v_new;
END;
$$;

-- ---------------------------------------------------------------------
-- v_balance_reconciliation: audit view - stored balance vs ledger total.
-- In a healthy database this returns ZERO rows.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_balance_reconciliation AS
SELECT a.account_number, a.balance AS stored_balance,
       COALESCE(SUM(CASE WHEN l.entry_type = 'CREDIT' THEN l.amount ELSE -l.amount END), 0) AS ledger_balance
FROM accounts a
LEFT JOIN ledger_entries l ON l.account_id = a.account_id
GROUP BY a.account_id, a.account_number, a.balance
HAVING a.balance <> COALESCE(SUM(CASE WHEN l.entry_type = 'CREDIT' THEN l.amount ELSE -l.amount END), 0);

SELECT 'fn_transfer, fn_reverse_transfer and v_balance_reconciliation created' AS status;

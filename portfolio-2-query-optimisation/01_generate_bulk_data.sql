-- =====================================================================
-- Otigba MFB - Portfolio 2: generate realistic VOLUME for performance tests
-- Adds 20,000 customers, 30,000 accounts, 200,000 transfers
-- (= 400,000 ledger lines) spread over the last 12 months.
-- All data is synthetic. Takes roughly 30-90 seconds on a laptop.
-- Prerequisite: Portfolio 1 scripts 01 and 02 already run.
-- =====================================================================

SELECT setseed(0.42);   -- makes the "random" data the same on every run

-- Turn the audit trigger off during the bulk load (re-enabled at the end)
ALTER TABLE accounts DISABLE TRIGGER trg_audit_accounts;

-- 1. Customers -------------------------------------------------------
INSERT INTO customers (bvn, first_name, last_name, email, phone,
                       date_of_birth, kyc_tier, home_branch_id, created_at)
SELECT '222' || lpad(g::text, 8, '0'),
       (ARRAY['Chinedu','Aisha','Kelechi','Bola','Ngozi','Yusuf','Ifeoma','Segun','Zainab','Obinna'])[1 + (random()*9)::int],
       (ARRAY['Eze','Abubakar','Okafor','Adebayo','Uche','Bello','Nnamdi','Ogun','Lawal','Obi'])[1 + (random()*9)::int],
       'cust' || g || '@example.com',
       '+23481' || lpad(g::text, 8, '0'),
       DATE '1956-01-01' + (random() * 17000)::int,          -- ages ~20 to ~70
       1 + (random()*2)::int,
       1 + (random()*3)::int,
       now() - (random() * INTERVAL '730 days')
FROM generate_series(1, 20000) AS g;

-- 2. Accounts: one per new customer + 10,000 second accounts ---------
INSERT INTO accounts (account_number, customer_id, account_type_code, opened_at)
SELECT '302' || lpad(g::text, 7, '0'),
       c.customer_id,
       (ARRAY['SAV_T1','SAV_T3','CURRENT'])[1 + (random()*2)::int],
       now() - INTERVAL '400 days'
FROM (SELECT customer_id, row_number() OVER (ORDER BY customer_id) AS rn
      FROM customers WHERE bvn LIKE '222%') c
JOIN generate_series(1, 30000) g ON c.rn = CASE WHEN g <= 20000 THEN g ELSE g - 20000 END;

-- 3. Opening deposit of N5,000,000 into every bulk account -----------
WITH t AS (
    INSERT INTO transactions (reference, txn_type, amount, channel, status, narration, created_at)
    SELECT 'OPN-' || a.account_number, 'DEPOSIT', 5000000, 'BRANCH', 'SUCCESSFUL',
           'Opening deposit', now() - INTERVAL '400 days'
    FROM accounts a WHERE a.account_number LIKE '302%'
    RETURNING txn_id, reference, created_at
)
INSERT INTO ledger_entries (txn_id, account_id, entry_type, amount, balance_after, created_at)
SELECT t.txn_id, a.account_id, 'CREDIT', 5000000, 5000000, t.created_at
FROM t JOIN accounts a ON a.account_number = substr(t.reference, 5);

-- 4. 200,000 transfers between random bulk accounts ------------------
CREATE TEMP TABLE tmp_transfers AS
SELECT g AS n,
       (SELECT min(account_id) FROM accounts WHERE account_number LIKE '302%') + (random()*29999)::int AS from_acct,
       round((100 + random()*49900)::numeric, 2)                                AS amount,
       (ARRAY['MOBILE','MOBILE','MOBILE','USSD','POS','WEB'])[1 + (random()*5)::int] AS channel,
       CASE WHEN random() < 0.03 THEN 'FAILED'
            WHEN random() < 0.01 THEN 'PENDING'
            ELSE 'SUCCESSFUL' END                                               AS status,
       now() - (random() * INTERVAL '365 days')                                 AS created_at
FROM generate_series(1, 200000) g;

ALTER TABLE tmp_transfers ADD COLUMN to_acct INT;
UPDATE tmp_transfers t
SET to_acct = CASE WHEN x.cand = t.from_acct THEN x.cand + 1 ELSE x.cand END
FROM (SELECT n, (SELECT min(account_id) FROM accounts WHERE account_number LIKE '302%')
                 + (random()*29998)::int AS cand FROM tmp_transfers) x
WHERE x.n = t.n;

INSERT INTO transactions (reference, txn_type, amount, channel, status, narration, created_at)
SELECT 'TRF-' || lpad(n::text, 9, '0'), 'TRANSFER', amount, channel, status,
       'Transfer to acct ' || to_acct, created_at
FROM tmp_transfers;

-- Only SUCCESSFUL transfers move money: one DEBIT + one CREDIT each
INSERT INTO ledger_entries (txn_id, account_id, entry_type, amount, balance_after, created_at)
SELECT tx.txn_id, leg.account_id, leg.entry_type, tt.amount, 0, tt.created_at
FROM tmp_transfers tt
JOIN transactions tx ON tx.reference = 'TRF-' || lpad(tt.n::text, 9, '0')
CROSS JOIN LATERAL (VALUES (tt.from_acct, 'DEBIT'), (tt.to_acct, 'CREDIT')) AS leg(account_id, entry_type)
WHERE tt.status = 'SUCCESSFUL';

-- 5. Running balance on every ledger line, then final account balance
UPDATE ledger_entries le
SET balance_after = r.running
FROM (SELECT entry_id,
             SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END)
                 OVER (PARTITION BY account_id ORDER BY created_at, entry_id) AS running
      FROM ledger_entries) r
WHERE le.entry_id = r.entry_id AND le.balance_after IS DISTINCT FROM r.running;

UPDATE accounts a
SET balance = s.bal
FROM (SELECT account_id,
             SUM(CASE WHEN entry_type = 'CREDIT' THEN amount ELSE -amount END) AS bal
      FROM ledger_entries GROUP BY account_id) s
WHERE a.account_id = s.account_id AND a.balance <> s.bal;

ALTER TABLE accounts ENABLE TRIGGER trg_audit_accounts;
DROP TABLE tmp_transfers;

-- Refresh the planner's statistics so it knows how big the tables are now
ANALYZE;

-- Row counts (evidence for the screenshot)
SELECT 'customers' AS table_name, count(*) FROM customers
UNION ALL SELECT 'accounts',       count(*) FROM accounts
UNION ALL SELECT 'transactions',   count(*) FROM transactions
UNION ALL SELECT 'ledger_entries', count(*) FROM ledger_entries;

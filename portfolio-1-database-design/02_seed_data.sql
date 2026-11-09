-- =====================================================================
-- Otigba MFB - Portfolio 1: sample (fictitious) reference and customer data
-- All names, BVNs, phone numbers and emails below are invented.
-- =====================================================================

INSERT INTO branches (branch_code, branch_name, city, state) VALUES
('LAG001', 'Yaba Hub',          'Lagos',         'Lagos'),
('ABJ001', 'Wuse II Hub',       'Abuja',         'FCT'),
('ONI001', 'Onitsha Main',      'Onitsha',       'Anambra'),
('DIG001', 'Digital (App-only)', 'Lagos',        'Lagos');

INSERT INTO account_types (account_type_code, description, daily_debit_limit, interest_rate_pct) VALUES
('SAV_T1',  'Tier 1 Savings (basic KYC)',  50000.00,   4.00),
('SAV_T3',  'Tier 3 Savings (full KYC)',   5000000.00, 4.00),
('CURRENT', 'Current account',             10000000.00, 0.00),
('TARGET',  'Locked target savings',       0.01,       12.00);

INSERT INTO customers (bvn, first_name, last_name, email, phone, date_of_birth, kyc_tier, home_branch_id) VALUES
('22100000001', 'Adaeze',   'Okonkwo', 'adaeze.okonkwo@example.com', '+2348030000001', '1990-04-12', 3, 1),
('22100000002', 'Tunde',    'Bakare',  'tunde.bakare@example.com',   '+2348030000002', '1985-11-03', 3, 1),
('22100000003', 'Halima',   'Musa',    'halima.musa@example.com',    '+2348030000003', '1998-07-21', 2, 2),
('22100000004', 'Emeka',    'Nwosu',   'emeka.nwosu@example.com',    '+2348030000004', '1979-01-30', 3, 3),
('22100000005', 'Funmi',    'Adeyemi', 'funmi.adeyemi@example.com',  '+2348030000005', '2000-09-09', 1, 4),
('22100000006', 'Ibrahim',  'Sani',    'ibrahim.sani@example.com',   '+2348030000006', '1993-02-17', 2, 2);

INSERT INTO accounts (account_number, customer_id, account_type_code) VALUES
('3010000001', 1, 'SAV_T3'),
('3010000002', 1, 'TARGET'),
('3010000003', 2, 'CURRENT'),
('3010000004', 3, 'SAV_T3'),
('3010000005', 4, 'CURRENT'),
('3010000006', 5, 'SAV_T1'),
('3010000007', 6, 'SAV_T3');

-- Opening deposits: each deposit = 1 transaction row + 1 CREDIT ledger line,
-- and the account balance is updated to match the ledger.
WITH opening(acct, amt, ref) AS (
    VALUES ('3010000001', 250000.00, 'DEP-0001'),
           ('3010000003', 900000.00, 'DEP-0002'),
           ('3010000004', 120000.00, 'DEP-0003'),
           ('3010000005', 1500000.00,'DEP-0004'),
           ('3010000006', 15000.00,  'DEP-0005'),
           ('3010000007', 60000.00,  'DEP-0006')
), t AS (
    INSERT INTO transactions (reference, txn_type, amount, channel, status, narration)
    SELECT ref, 'DEPOSIT', amt, 'BRANCH', 'SUCCESSFUL', 'Opening deposit' FROM opening
    RETURNING txn_id, reference, amount
)
INSERT INTO ledger_entries (txn_id, account_id, entry_type, amount, balance_after)
SELECT t.txn_id, a.account_id, 'CREDIT', t.amount, t.amount
FROM t JOIN opening o ON o.ref = t.reference
       JOIN accounts a ON a.account_number = o.acct;

UPDATE accounts a
SET balance = l.total
FROM (SELECT account_id, SUM(amount) AS total
      FROM ledger_entries WHERE entry_type = 'CREDIT' GROUP BY account_id) l
WHERE a.account_id = l.account_id;

-- Show the result: customers, their accounts and balances
SELECT c.first_name || ' ' || c.last_name AS customer,
       a.account_number, a.account_type_code, a.balance, a.status
FROM customers c JOIN accounts a ON a.customer_id = c.customer_id
ORDER BY c.customer_id, a.account_number;

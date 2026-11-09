-- =====================================================================
-- Otigba MFB - Portfolio 1: proving that the keys and constraints work
-- Run each statement ONE AT A TIME in pgAdmin.
-- Every statement below is EXPECTED TO FAIL.
-- =====================================================================

-- Test 1: PRIMARY/UNIQUE key - duplicate BVN is rejected
INSERT INTO customers (bvn, first_name, last_name, email, phone, date_of_birth, home_branch_id)
VALUES ('22100000001', 'Copy', 'Cat', 'copy@example.com', '+2348030009999', '1990-01-01', 1);


-- Test 2: FOREIGN KEY - account for a customer who does not exist
INSERT INTO accounts (account_number, customer_id, account_type_code)
VALUES ('3019999999', 999, 'SAV_T1');


-- Test 3: CHECK - balance can never go negative (no overdraft)
UPDATE accounts SET balance = -500 WHERE account_number = '3010000006';


-- Test 4: CHECK - customer must be at least 18 years old
INSERT INTO customers (bvn, first_name, last_name, email, phone, date_of_birth, home_branch_id)
VALUES ('22100000099', 'Young', 'Person', 'young@example.com', '+2348030008888', CURRENT_DATE - INTERVAL '10 years', 1);


-- Test 5: CHECK - BVN must be exactly 11 digits
INSERT INTO customers (bvn, first_name, last_name, email, phone, date_of_birth, home_branch_id)
VALUES ('12345', 'Bad', 'Bvn', 'badbvn@example.com', '+2348030007777', '1990-01-01', 1);


-- Test 6: CHECK - transaction amount must be positive
INSERT INTO transactions (reference, txn_type, amount, channel)
VALUES ('TEST-NEG', 'DEPOSIT', -100, 'MOBILE');


--  The auditlog Record 
SELECT audit_id, record_id AS account_id, action,
       old_data->>'balance' AS old_balance, new_data->>'balance' AS new_balance, performed_at
FROM audit_log ORDER BY audit_id;

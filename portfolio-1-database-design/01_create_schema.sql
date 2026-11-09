-- =====================================================================
-- Otigba MFB (simulated digital microfinance bank)
-- Portfolio 1: Database Design and Modelling - relational schema
-- Author : Ezeonwumere Chidiebere - 301923965
-- DBMS   : PostgreSQL 16+
-- Run    : connect to database otigba_mfb, then run this whole file
-- =====================================================================

-- Start clean so the script can be re-run safely
DROP TABLE IF EXISTS audit_log, ledger_entries, transactions, accounts,
                     account_types, customers, branches CASCADE;

-- ---------------------------------------------------------------------
-- 1. BRANCHES - physical/virtual service locations
-- ---------------------------------------------------------------------
CREATE TABLE branches (
    branch_id     SERIAL       PRIMARY KEY,
    branch_code   VARCHAR(6)   NOT NULL UNIQUE,
    branch_name   VARCHAR(100) NOT NULL,
    city          VARCHAR(60)  NOT NULL,
    state         VARCHAR(30)  NOT NULL
);

-- ---------------------------------------------------------------------
-- 2. CUSTOMERS - people who own accounts
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id    SERIAL       PRIMARY KEY,
    bvn            CHAR(11)     NOT NULL UNIQUE
                   CHECK (bvn ~ '^[0-9]{11}$'),          -- 11-digit BVN
    first_name     VARCHAR(50)  NOT NULL,
    last_name      VARCHAR(50)  NOT NULL,
    email          VARCHAR(120) NOT NULL UNIQUE,
    phone          VARCHAR(14)  NOT NULL UNIQUE,
    date_of_birth  DATE         NOT NULL
                   CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years'),
    kyc_tier       SMALLINT     NOT NULL DEFAULT 1
                   CHECK (kyc_tier BETWEEN 1 AND 3),
    home_branch_id INT          NOT NULL REFERENCES branches(branch_id),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 3. ACCOUNT_TYPES - product rules (kept separate for 3NF)
-- ---------------------------------------------------------------------
CREATE TABLE account_types (
    account_type_code VARCHAR(10)   PRIMARY KEY,
    description       VARCHAR(100)  NOT NULL,
    daily_debit_limit NUMERIC(18,2) NOT NULL CHECK (daily_debit_limit > 0),
    interest_rate_pct NUMERIC(5,2)  NOT NULL DEFAULT 0
                      CHECK (interest_rate_pct >= 0)
);

-- ---------------------------------------------------------------------
-- 4. ACCOUNTS - one customer can own many accounts
-- ---------------------------------------------------------------------
CREATE TABLE accounts (
    account_id        SERIAL        PRIMARY KEY,
    account_number    CHAR(10)      NOT NULL UNIQUE
                      CHECK (account_number ~ '^[0-9]{10}$'), -- NUBAN length
    customer_id       INT           NOT NULL REFERENCES customers(customer_id),
    account_type_code VARCHAR(10)   NOT NULL REFERENCES account_types(account_type_code),
    currency          CHAR(3)       NOT NULL DEFAULT 'NGN',
    balance           NUMERIC(18,2) NOT NULL DEFAULT 0
                      CHECK (balance >= 0),                    -- no overdraft
    status            VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE'
                      CHECK (status IN ('ACTIVE','FROZEN','CLOSED')),
    opened_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. TRANSACTIONS - one business event (deposit, transfer, ...)
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
    txn_id          BIGSERIAL     PRIMARY KEY,
    reference       VARCHAR(30)   NOT NULL UNIQUE,   -- idempotency key
    txn_type        VARCHAR(12)   NOT NULL
                    CHECK (txn_type IN ('DEPOSIT','WITHDRAWAL','TRANSFER','REVERSAL')),
    amount          NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    channel         VARCHAR(8)    NOT NULL
                    CHECK (channel IN ('MOBILE','USSD','POS','WEB','BRANCH')),
    status          VARCHAR(10)   NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING','SUCCESSFUL','FAILED','REVERSED')),
    narration       VARCHAR(140),
    reversed_txn_id BIGINT        REFERENCES transactions(txn_id), -- self-reference
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 6. LEDGER_ENTRIES - double-entry lines (each DEBIT has a matching CREDIT)
-- ---------------------------------------------------------------------
CREATE TABLE ledger_entries (
    entry_id      BIGSERIAL     PRIMARY KEY,
    txn_id        BIGINT        NOT NULL REFERENCES transactions(txn_id),
    account_id    INT           NOT NULL REFERENCES accounts(account_id),
    entry_type    CHAR(6)       NOT NULL CHECK (entry_type IN ('DEBIT','CREDIT')),
    amount        NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    balance_after NUMERIC(18,2) NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (txn_id, account_id, entry_type)        -- composite candidate key
);

-- ---------------------------------------------------------------------
-- 7. AUDIT_LOG - who changed what (supports "audit account balances")
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id     BIGSERIAL    PRIMARY KEY,
    table_name   VARCHAR(40)  NOT NULL,
    record_id    BIGINT       NOT NULL,
    action       VARCHAR(10)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_data     JSONB,
    new_data     JSONB,
    performed_by VARCHAR(60)  NOT NULL DEFAULT current_user,
    performed_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Trigger: every change to an account's balance/status is written to audit_log
CREATE OR REPLACE FUNCTION fn_audit_accounts() RETURNS trigger AS $$
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_data, new_data)
    VALUES ('accounts', NEW.account_id, TG_OP,
            CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END,
            to_jsonb(NEW));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_accounts
AFTER INSERT OR UPDATE OF balance, status ON accounts
FOR EACH ROW EXECUTE FUNCTION fn_audit_accounts();

-- Quick check: list the tables just created
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' ORDER BY table_name;

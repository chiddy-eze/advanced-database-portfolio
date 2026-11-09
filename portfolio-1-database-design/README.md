# Portfolio 1 – Database Design and Modelling

**Student:** Ezeonwumere Chidiebere - 301923965
**Course:** MIT 8103 Advanced Database Systems
**DBMS:** PostgreSQL 16+ with pgAdmin 4

## 1. Selected case study: Otigba MFB (A simulated Digital Bank)

| Item | Description |
|---|---|
| Organisation | **Otigba MFB**, a fictitious Nigerian digital microfinance bank. It serves retail customers mainly through a mobile app and USSD, and it also has a few physical branches. |
| Nature of the system | The core banking ledger: customer onboarding (KYC), account opening, deposits, withdrawals, transfers between customers, reversal of failed transfers and audit of balances. |
| Database users | **Customers** (indirectly, through the app), **customer support officers** (look up customers and transactions), **operations staff** (reverse failed transactions), **compliance/audit officers** (review audit logs and balances) and **data analysts** (reporting). |
| Major data stored | Branches, customers (BVN, contact details, KYC tier), account types, accounts and balances, transactions, double-entry ledger lines and an audit trail. |
| Key operations | Open an account, deposit, withdraw, transfer funds, reverse a failed transfer, view a statement, and check that every balance matches its ledger. |

The same case study is used in all five portfolio activities. All data is invented.

## 2. Entities and relationships

| Relationship | Cardinality | Meaning |
|---|---|---|
| Branch → Customer | 1 : 0..N | Every customer has one home branch. A branch can have many customers. |
| Customer → Account | 1 : 1..N | A customer owns one or more accounts. |
| Account type → Account | 1 : 0..N | The product rules (limit, interest) are defined once and shared by many accounts. |
| Transaction → Ledger entry | 1 : 1..N | A deposit creates 1 entry. A transfer creates 2 entries (a DEBIT and a matching CREDIT). |
| Account → Ledger entry | 1 : 0..N | Every movement of money on an account is a ledger line. |
| Transaction → Transaction | 0..1 : 0..1 | A REVERSAL transaction points to the transaction it reverses. |
| Account → Audit log | 1 : 0..N | A trigger records every change to an account's balance or status. |

ER diagram: [`er_diagram.png`](er_diagram.png) (source: `er_diagram.mmd`).

## 3. Keys and constraints

| Type | Where | Why it matters for a bank |
|---|---|---|
| Primary keys (surrogate) | `customer_id`, `account_id`, `txn_id` … | Short, stable internal identifiers that never change, even if a phone number does. |
| Unique (natural/candidate) keys | `bvn`, `email`, `phone`, `account_number`, `reference` | Stop duplicate customers and duplicate transactions. `reference` also works as an idempotency key, so a transfer that is retried is not posted twice. |
| Foreign keys | `accounts.customer_id`, `ledger_entries.account_id` … | Prevent "orphan" records, such as an account with no owner. |
| Composite unique key | `ledger_entries (txn_id, account_id, entry_type)` | The same transaction cannot debit the same account twice. |
| CHECK constraints | `balance >= 0`, `amount > 0`, BVN = 11 digits, age ≥ 18, `kyc_tier` 1–3, status lists | Business rules are enforced by the database itself, not only by the app. |
| Trigger | `trg_audit_accounts` | Writes an automatic audit trail of balance and status changes. |

Proof: `03_constraint_tests.sql` tries to break each rule, and all six attempts are rejected (see `screenshots/`).

## 4. Normalisation

**Starting point (unnormalised):** imagine a single spreadsheet of transfers, where each row holds the customer name, BVN, phone, branch name, branch city, account number, account type, daily limit, interest rate, transaction reference, amount, and so on. One customer with several accounts appears many times, and some cells hold lists (for example, "accounts: 301…01, 301…02").

| Normal form | Problem found | Fix applied |
|---|---|---|
| **1NF** – atomic values, no repeating groups | One cell held several account numbers | One row per account and one row per ledger line, so every column holds a single value. |
| **2NF** – no partial dependency on part of a key | In a table keyed on (`txn_id`, `account_id`), the `amount`, `channel` and `narration` depend only on `txn_id` | Split into `transactions` (facts about the event) and `ledger_entries` (facts about each account leg). |
| **3NF** – no transitive dependency | `daily_debit_limit` and `interest_rate` depend on the *account type*, not on the account. `branch city` depends on the *branch*, not on the customer | Moved them into `account_types` and `branches`, which are referenced by foreign keys. |

**Result:** each fact is stored once. If the Tier 1 daily limit changes, we update one row in `account_types` instead of thousands of account rows. This removes update, insert and delete anomalies.

**Deliberate denormalisation:** `accounts.balance` could always be calculated as SUM(credits) − SUM(debits) from `ledger_entries`. It is stored anyway because balance checks happen on every transfer and must be fast. To keep it safe, the balance is only changed inside transactions (Portfolio 3), and the audit trigger plus a reconciliation query check that it matches the ledger.

## 5. How to run

1. In pgAdmin, create a database called `otigba_mfb`.
2. Open the **Query Tool** on that database and run `01_create_schema.sql`, then `02_seed_data.sql`.
3. Run each statement in `03_constraint_tests.sql` **one at a time**. Each one should show an error message, which is the expected result.

## 6. Evidence (`screenshots/`)

- `p1_01_tables_created.png`: the tables listed in pgAdmin
- `p1_02_seed_result.png`: customers, accounts and balances
- `p1_03_constraint_errors.png`: the rejected inserts and updates
- `p1_04_audit_log.png`: rows written by the audit trigger

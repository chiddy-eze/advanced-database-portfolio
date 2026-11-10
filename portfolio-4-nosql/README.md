# Portfolio 4 – NoSQL and Advanced Data Models (MongoDB)

**Case study:** Otigba MFB (simulated digital microfinance bank), the same customers as Portfolios 1–3
**Platform:** MongoDB Atlas (free M0 cluster `otigba-cluster`, 3-node replica set) + MongoDB Compass / mongosh
**NoSQL model used:** **Document** model, plus a **key-value** pattern (OTP sessions with TTL expiry)

## 1. Why a document model for part of Otigba MFB?

The core ledger stays in PostgreSQL (Portfolios 1–3), because double-entry money movement needs strict relational integrity. Several other parts of a digital bank fit a document database better:

| Data | Why it suits documents |
|---|---|
| **Customer profile + KYC** | The app's home screen needs the customer, their KYC documents and *all* their accounts. In PostgreSQL that takes 3 joins. Here it is **one document, one read**. |
| **Optional attributes** | Only some customers have devices or a business profile. In SQL that means nullable columns or extra tables. In MongoDB those fields are simply present or absent (flexible schema). |
| **Transaction metadata per channel** | A POS payment has a terminal and merchant, USSD has a short code and telco, mobile has a device and GPS location. Each channel's document carries only its own fields (a polymorphic schema). |
| **OTP / session tokens** | A key → value lookup that must disappear after 5 minutes. A **TTL index** deletes them automatically. |

## 2. Data model

### `customers` – accounts **embedded** (one-to-few)

```json
{
  "_id": "CUS-000001",
  "bvn": "22100000001",
  "name":    { "first": "Adaeze", "last": "Okonkwo" },
  "contact": { "email": "adaeze.okonkwo.1@example.com", "phone": "+2348030000001" },
  "kyc":     { "tier": 3, "documents": [ { "type": "NIN", "status": "VERIFIED" } ] },
  "home_branch": { "code": "LAG001", "name": "Yaba Hub" },
  "accounts": [
    { "account_number": "3010000001", "type": "SAV_T3", "currency": "NGN",
      "balance": { "$numberDecimal": "250000.00" }, "status": "ACTIVE" }
  ],
  "devices": [ { "device_id": "DEV-00007", "os": "Android" } ],
  "business_profile": { "business_name": "Okafor Ventures", "cac_number": "RC123456" }
}
```

`devices` and `business_profile` are optional: 290 of the 500 customers have devices and 48 have a business profile.

### `transactions` – **referenced** by account number (one-to-many, unbounded)

```json
{
  "_id": "TRF-0000001",
  "type": "TRANSFER", "amount": { "$numberDecimal": "12500.00" }, "status": "SUCCESSFUL",
  "channel": "POS", "created_at": { "$date": "2026-10-02T09:14:00Z" },
  "legs": [ { "account_number": "3030000045", "customer_id": "CUS-000045", "direction": "DEBIT" },
            { "account_number": "3030000311", "customer_id": "CUS-000311", "direction": "CREDIT" } ],
  "channel_details": { "terminal_id": "2OTG4821", "merchant_name": "Shoprite Ikeja", "mcc": "5411" }
}
```

### `otp_sessions` – key-value with expiry

`{ "_id": "otp:+2348030000001", "code": "482913", "created_at": <date> }`, deleted automatically after 300 seconds.

### Modelling decisions

| Decision | Choice | Reason |
|---|---|---|
| Accounts inside customer? | **Embed** | A customer has only a few accounts, which are always shown together. One read, and an update to a single document is atomic. |
| Transactions inside customer? | **Reference** | Transactions grow forever. Embedding them would push documents past MongoDB's 16 MB limit and make every profile read slow. |
| Branch | **Denormalised snapshot** (code + name) | Branch names rarely change. Copying them avoids a lookup on every read, which is a deliberate trade-off against 3NF. |
| Transaction `_id` | The business reference (`TRF-…`) | Uniqueness of `_id` gives free idempotency, so a retried transfer can never be stored twice. |
| Money type | **Decimal128** (`NumberDecimal`) | Exact arithmetic. Floating point would give N0.30000000000000004-style errors. |

## 3. Relational (PostgreSQL) vs document (MongoDB)

| | PostgreSQL (P1–P3) | MongoDB (P4) |
|---|---|---|
| Structure | 7 normalised tables (3NF) | 3 collections, embedded sub-documents |
| Customer + accounts | JOIN of 3 tables | 1 `findOne` |
| Schema | Fixed. Adding a column needs `ALTER TABLE` | Flexible, with optional rules via `$jsonSchema` |
| Integrity | FK, CHECK, UNIQUE | `$jsonSchema` validation + unique indexes. **No foreign keys**: the application must keep references valid |
| Transactions | ACID by default | Single document: always atomic. Multiple documents: ACID transactions on a replica set (Block 10) |
| Scaling | Mainly vertical, plus read replicas | Built for horizontal scaling (sharding, see Portfolio 5) |
| Best for at Otigba MFB | **The ledger and balances** | **Profiles/KYC, channel metadata, sessions, app activity** |

## 4. What was implemented and tested

| Block | Demonstrates | Result |
|---|---|---|
| Setup | `$jsonSchema` validators, 7 indexes (unique, compound, multikey, 2dsphere, TTL) | Collections and indexes listed |
| 1 | Flexible schema | Customers with and without devices or business profile |
| 2 | Embedded read | The full profile, KYC and accounts in a single document |
| 4–5 | **Query optimisation** with `explain("executionStats")` | COLLSCAN examined all ~5,548 documents. **IXSCAN on `ix_statement`** examined only the matching ones |
| 6 | Aggregation pipeline (`$match` → `$group` → `$sort`) | Transfer value per channel over 30 days |
| 7 | `$unwind` + `$lookup` (a join in MongoDB) | Top 5 senders with their names |
| 8 | Polymorphic documents + **geospatial query** | POS vs USSD shapes. Mobile transfers within 15 km of Yaba |
| 10 | **Multi-document ACID transaction** | Commit: Adaeze −25,000, Tunde +25,000, and a transaction document |
| 11 | Atomicity | Tunde's credit is undone when Funmi's debit fails, so the transaction aborts |
| 12 | Validation | Bad BVN, tier 5 and negative balance give "Document failed validation". Duplicate BVN gives E11000 |
| 13 | Key-value + TTL | The OTP is found by key, then disappears after about 5–6 minutes |
| 14 | Audit | 0 accounts where the embedded balance differs from the transaction history |

## 5. Suitability and limitations

- **Suitable:** read-heavy, document-shaped data (profiles, KYC, app sessions, notifications, transaction metadata) and data whose shape changes often as new channels or products are added.
- **Limitations seen:** no foreign keys, so the application must keep `customer_id` references valid. Denormalised copies (branch name) can go stale. Multi-document transactions work but are slower than single-document updates, so the model is designed so that most updates touch one document.
- **Conclusion:** a **polyglot** design. PostgreSQL remains the system of record for money, and MongoDB serves the customer-facing profile and activity data.

## 6. How to run

1. In Compass, connect to `otigba-cluster`. In the **`>_ MONGOSH`** panel, type `use otigba_mfb` and press Enter.
2. Paste the whole of `01_setup_collections.js` and press Enter. Screenshot the result (`p4_01`).
3. **Import data** (Compass): in the left sidebar, open `otigba_mfb` → `customers` → **Add Data → Import JSON or CSV file** → choose `data/customers.json` → **Import**. Repeat for `transactions` with `data/transactions.json`.
4. In `02_queries_and_demos.js`, paste **one block at a time** and screenshot each `[SCREENSHOT]`.

`generate_data.py` regenerates the data files (Python 3, fixed random seed).

## 7. Evidence (`screenshots/`)

| # | File | Shows |
|---|---|---|
| 01 | `p4_01_setup_collections_indexes.png` | Collections and indexes created |
| 02 | `p4_02_counts_flexible_schema.png` | Document counts and optional fields |
| 03 | `p4_03_q1_customer_document.png` | One customer document with embedded accounts |
| 04 | `p4_04_q2_plan_collscan.png` | Forced collection scan |
| 05 | `p4_05_q2_plan_ixscan.png` | Index scan on `ix_statement` |
| 06 | `p4_06_q2_statement_rows.png` | Statement rows |
| 07 | `p4_07_q3_channel_totals.png` | Aggregation by channel |
| 08 | `p4_08_q4_top_senders.png` | `$lookup` join result |
| 09 | `p4_09_q5_polymorphic_geo.png` | POS/USSD shapes and geo count |
| 10 | `p4_10_balances_before.png` | Balances before the transactions |
| 11 | `p4_11_transaction_committed.png` | COMMITTED and new balances |
| 12 | `p4_12_transaction_aborted.png` | ABORTED and balances unchanged |
| 13 | `p4_13_validation_errors.png` | Validation and duplicate-key rejections |
| 14 | `p4_14_ttl_otp_created.png` | OTP stored and TTL index |
| 15 | `p4_15_ttl_otp_expired.png` | OTP gone after expiry |
| 16 | `p4_16_reconciliation.png` | 0 mismatched balances |

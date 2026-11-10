# Portfolio 2 – Query Processing and Optimisation

**Case study:** Otigba MFB (simulated digital microfinance bank), using the same schema as Portfolio 1
**DBMS:** PostgreSQL 16+ / pgAdmin 4

## 1. Aim

To show how PostgreSQL processes four everyday Otigba MFB queries, read the **execution plans**, and measure how much well-chosen **indexes** improve them on a realistic data volume.

## 2. Test data volume (`01_generate_bulk_data.sql`)

| Table | Rows |
|---|---|
| customers | ~20,000 |
| accounts | ~30,000 |
| transactions | ~230,000 (12 months of transfers; about 3% FAILED, 1% PENDING) |
| ledger_entries | ~414,000 (a DEBIT and a CREDIT line for every successful transfer) |

The data is synthetic and generated with `generate_series()` and a fixed random seed, so the results can be repeated. Account balances still match their ledger lines.

## 3. The four business queries (`02_benchmark_queries.sql`)

| # | Who needs it | Query |
|---|---|---|
| Q1 | Customer support | 90-day statement for one account (joins 3 tables) |
| Q2 | Operations | FAILED transfers in the last 7 days, to be reversed |
| Q3 | Customer support | Find a customer by e-mail, ignoring capital letters |
| Q4 | Analytics | Value of successful transfers per channel over 30 days |

## 4. Indexes created (`03_create_indexes.sql`)

| Index | Type | Why |
|---|---|---|
| `idx_ledger_account_created (account_id, created_at DESC)` | Composite B-tree | PostgreSQL does **not** index foreign-key columns automatically, so Q1 read all ~414k ledger lines to find one account's few rows. |
| `idx_txn_failed_created (created_at) WHERE status='FAILED'` | **Partial** | Only about 3% of rows are FAILED, so the index stays tiny (around 150 kB) and adds almost no cost to normal inserts. |
| `idx_customers_lower_email (lower(email))` | **Expression** | An ordinary index on `email` cannot be used once the query applies `lower()` to the column. |
| `idx_txn_created_covering (created_at) INCLUDE (...)` | **Covering** | Holds every column Q4 needs, so the query is answered from the index alone (an Index Only Scan) without visiting the table. |

## 5. Results (my machine)

*Execution Time from `EXPLAIN (ANALYZE, BUFFERS)`, the last of 3 runs.*

| Query | Plan BEFORE | Time before (ms) | Plan AFTER | Time after (ms) | Speed-up |
|---|---|---|---|---|---|
| Q1 Statement | Parallel Seq Scan on ledger_entries | 195.358 | Index Scan using idx_ledger_account_created | 0.168 | 1,163× |
| Q2 Failed txns | Parallel Seq Scan on transactions | 67.267 | Index Scan using idx_txn_failed_created | 0.175 | 384× |
| Q3 Email lookup | Seq Scan on customers | 10.099 | Index Scan using idx_customers_lower_email | 0.074 | 136× |
| Q4 Channel totals | Parallel Seq Scan on transactions | 214.096 | Index Only Scan using idx_txn_created_covering | 13.255 | 16× |

## 6. Performance analysis

- **The biggest gain is Q1.** Before the index, the database read the whole ledger, every customer's history, to return a handful of rows for one account. With the composite index it jumps straight to that account's lines, and they are already in date order, so no separate sort is needed. This is the query a support agent runs most often, so it matters most.
- **Q2 shows the value of a partial index.** It indexes only the small set of FAILED rows that operations staff care about, so it is fast to search and cheap to keep up to date.
- **Q3 shows a common trap:** applying a function to a column in the WHERE clause stops a normal index being used. The expression index matches the query exactly.
- **Q4 gains the least.** It still has to add up about 15,000 rows, and an index cannot remove that work. The covering index only avoids reading the table pages. For heavier reporting, a materialised view or a separate reporting replica (see Portfolio 5) would be better.
- **Trade-offs:** indexes are not free. The four indexes use extra disk space (see the size list from `03_create_indexes.sql`), and every INSERT into `transactions` and `ledger_entries` must now also update them. A bank writes far more transactions than it reads statements, so only indexes that serve frequent, important queries were added. The existing UNIQUE keys (`reference`, `account_number`) already provide indexes automatically.
- **Planner statistics:** `ANALYZE` was run after the bulk load. Without it, the planner's row estimates are wrong and it can choose a poor plan.

## 7. How to run

1. Run `01_generate_bulk_data.sql` (about 30–90 seconds). Screenshot the row counts.
2. In `02_benchmark_queries.sql`, highlight **one** block at a time and press F5. Record the plan and *Execution Time*. These are your **BEFORE** results.
3. Run `03_create_indexes.sql` **in three parts**: the CREATE INDEX statements, then each `VACUUM ANALYZE` line on its own, then the final SELECT. pgAdmin runs a multi-statement selection as one transaction, and VACUUM is not allowed inside a transaction. Screenshot the list of indexes.
4. Repeat step 2. These are your **AFTER** results. Fill in the table in section 5.
5. (Optional) `04_drop_indexes_reset.sql` removes the indexes so the test can be repeated.

## 8. Evidence (`screenshots/`)

- `p2_01_bulk_row_counts.png`
- `p2_02_q1_statement_results.png`
- `p2_03_before_q1.png` … `p2_06_before_q4.png`
- `p2_07_indexes_created.png`
- `p2_08_after_q1.png` … `p2_11_after_q4.png`

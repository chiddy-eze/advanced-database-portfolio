# Portfolio 3 – Transactions and Concurrency

**Case study:** Otigba MFB (simulated digital microfinance bank), same database as Portfolios 1–2
**DBMS:** PostgreSQL 16+ / pgAdmin 4 (default isolation level: READ COMMITTED)

## 1. Why this matters for Otigba MFB

A transfer is several database changes that must behave as **one unit**:

1. Insert the transaction record.
2. Debit the sender.
3. Credit the receiver.
4. Write two ledger lines.

If the system stopped after step 2, money would vanish. And if a customer's app and a POS terminal debit the same account at the same moment, one debit must not overwrite the other. This activity shows how PostgreSQL's transactions (ACID) and concurrency control prevent both problems.

## 2. Files

| File | Purpose |
|---|---|
| `01_transfer_functions.sql` | `fn_transfer` (checks + row locking + double-entry), `fn_reverse_transfer`, and the audit view `v_balance_reconciliation` |
| `02_commit_rollback_demos.sql` | Demos 1–7: COMMIT, atomic failure, idempotency, ROLLBACK, error mid-transaction, SAVEPOINT, reversal, audit |
| `03a_concurrency_session_A.sql` / `03b_concurrency_session_B.sql` | Two simultaneous sessions (two pgAdmin Query Tool tabs) on the same account |
| `04_lock_monitor.sql` | Third tab: shows which session is waiting and which is blocking it |

## 3. ACID as demonstrated

| Property | Meaning | Evidence |
|---|---|---|
| **Atomicity** | All of a transaction happens, or none of it | Demo 2: a failed transfer saves nothing. Demo 4: the credit is undone when the debit fails. |
| **Consistency** | Rules are never broken | CHECK `balance >= 0` stops overdrafts. The UNIQUE `reference` stops double posting (Demo 2b). `v_balance_reconciliation` returns 0 rows. |
| **Isolation** | Concurrent transactions don't corrupt each other | Scenarios 2 and 3 below |
| **Durability** | Committed data survives | After COMMIT (Demo 1), the change is visible from every other session and stays after a pgAdmin/server restart. |

## 4. Commit / rollback results (`02_commit_rollback_demos.sql`)

| Demo | What happens | Result |
|---|---|---|
| 1 COMMIT | Adaeze sends N25,000 to Tunde | Both balances change permanently |
| 2 Atomic failure | Funmi (N15,000) tries to send N20,000 | `ERROR: Insufficient funds`. **0 rows** saved for that reference |
| 2b Idempotency | The same reference is sent again (like an app retry) | `duplicate key … transactions_reference_key`, so no double debit |
| 3 ROLLBACK | An operator runs `UPDATE accounts SET status='FROZEN'` with no WHERE | ~30,000 accounts frozen inside the transaction. ROLLBACK brings it back to 0 |
| 4 Error mid-way | Tunde credited, then Funmi's debit breaks the CHECK constraint | The whole transaction is rolled back, so Tunde does not keep the credit |
| 5 SAVEPOINT | Good transfer, then a failing one, in one block | The failing part is rolled back to the savepoint. The good transfer is kept |
| 6 Reversal | P3-TRF-001 reversed | A new REVERSAL transaction, original marked REVERSED, balances restored |
| 7 Audit | `SELECT * FROM v_balance_reconciliation` | 0 rows: every balance equals its ledger |

## 5. Concurrency scenarios (`03a` / `03b` / `04`)

Account 3010000007 starts with N60,000. Session A (mobile app) sends N20,000 and Session B (POS) charges N10,000. The correct final balance is **N30,000**.

| Scenario | Technique | What happened | Final balance |
|---|---|---|---|
| 1 Problem | READ COMMITTED; the app reads the balance, calculates, then writes a fixed number | Both read 60,000. B wrote 50,000, then A wrote 40,000 over it. The audit_log shows two updates that both started from 60,000 | **N40,000 ✗** (N10,000 lost) |
| 2 Fix 1 | **Pessimistic locking**: `SELECT … FOR UPDATE` | B's SELECT **waited** (the lock monitor shows `wait_event_type = Lock`, `blocked_by_pid = A`). Once A committed, B saw 40,000 and debited from that | **N30,000 ✓** |
| 3 Fix 2 | **REPEATABLE READ** isolation | B kept seeing its snapshot (60,000) after A committed. Its UPDATE failed with `could not serialize access due to concurrent update`. B rolled back and retried | **N30,000 ✓** |
| 4 Deadlock | Two transfers lock the same two accounts in opposite order | PostgreSQL detected the cycle and cancelled one session (`deadlock detected`) | No corruption; the cancelled one must retry |

## 6. Analysis

- **The lost update is a real risk.** The default READ COMMITTED level does not stop it when an application reads a value and writes back a number it calculated itself. Two safer patterns:
  1. Let the database do the arithmetic (`balance = balance - 20000`) on a row that is locked.
  2. Use a stricter isolation level and retry on error.
- **Pessimistic vs optimistic.** `FOR UPDATE` makes others wait, which is simple and safe for hot rows like a single account's balance. REPEATABLE READ / SERIALIZABLE lets work proceed without waiting but needs retry logic in the application. `fn_transfer` uses the pessimistic approach, because a short wait is acceptable for a payment, while a failed customer transfer is not.
- **Deadlock prevention.** `fn_transfer` and `fn_reverse_transfer` always lock the two accounts in a **fixed order** (lowest number first), so the circular wait in Scenario 4 cannot happen in real transfers.
- **Defence in depth.** Even if application code is wrong, the CHECK constraint, the UNIQUE reference, the audit trigger and the reconciliation view catch the problem.

## 7. How to run

1. Run `01_transfer_functions.sql` once (F5 on the whole file).
2. In `02_commit_rollback_demos.sql`, highlight **one statement at a time** and press F5. For Demo 5, highlight the whole `DO $$ … $$;` block and check the **Messages** tab.
3. Open **three** Query Tool tabs on `otigba_mfb`: load `03a` in tab 1, `03b` in tab 2 and `04` in tab 3. Follow the **step numbers** in order, switching tabs where the comments say. Each pgAdmin tab is a separate database connection, which simulates two users.
4. Finish with steps 5.1–5.2 (reset and audit check: 0 rows).

> If pgAdmin rolls a transaction back automatically after an error, a following `ROLLBACK` shows "there is no transaction in progress". That warning is harmless.

## 8. Evidence (`screenshots/`)

**Commit / rollback demos (`02_commit_rollback_demos.sql`)**

| # | File | Shows |
|---|---|---|
| 01 | `p3_01_balances_before.png` | The four balances before any demo |
| 02 | `p3_02_demo1_after_commit.png` | Adaeze −25,000, Tunde +25,000 after COMMIT |
| 03 | `p3_03_demo2_insufficient_funds.png` | Failed transfer error |
| 04 | `p3_04_demo2_no_rows_saved.png` | 0 rows saved for P3-TRF-002 |
| 05 | `p3_05_demo2b_duplicate_reference.png` | Duplicate reference rejected |
| 06 | `p3_06_demo3_frozen_before_rollback.png` | ~30,000 accounts frozen inside the transaction |
| 07 | `p3_07_demo3_after_rollback.png` | 0 frozen after ROLLBACK |
| 08 | `p3_08_demo4_check_error.png` | CHECK constraint stops the debit |
| 09 | `p3_09_demo4_tunde_unchanged.png` | Tunde did not keep the credit |
| 10 | `p3_10_demo5_savepoint_messages.png` | Savepoint NOTICE messages |
| 11 | `p3_11_demo5_only_trf003.png` | Only the good transfer exists |
| 12 | `p3_12_demo6_reversal.png` | Reversal and original marked REVERSED |
| 13 | `p3_13_demo7_reconciliation.png` | Audit view: 0 rows |

**Concurrency (`03a` / `03b` / `04`)**

| # | File | Shows |
|---|---|---|
| 14 | `p3_14_s1_lost_update_40000.png` | Wrong balance N40,000 |
| 15 | `p3_15_s1_audit_log.png` | Two updates both starting from 60,000 |
| 16 | `p3_16_s2_lock_monitor.png` | Session B waiting, blocked by Session A |
| 17 | `p3_17_s2_b_released_40000.png` | B released, sees 40,000 |
| 18 | `p3_18_s2_final_30000.png` | Correct N30,000 |
| 19 | `p3_19_s3_snapshot_60000.png` | B still sees its snapshot of 60,000 |
| 20 | `p3_20_s3_serialization_error.png` | Serialization error |
| 21 | `p3_21_s3_retry_30000.png` | Retry gives the correct N30,000 |
| 22 | `p3_22_s4_deadlock.png` | Deadlock detected (optional) |
| 23a | `p3_23a_audit_mismatch_detected.png` | Audit view caught a N1,000 mismatch on 3010000005, left by a missed BEGIN during Scenario 4 |
| 23 | `p3_23_final_reconciliation.png` | After the repair (step 5.3): final audit, 0 rows |

**What went wrong in Scenario 4, and how it was fixed:** on my first attempt, one session was not inside a transaction, because a `BEGIN` did not take effect. Its UPDATE was committed straight away, so the lock cycle never formed, and the other session waited indefinitely (over 5 minutes) instead of getting a deadlock error. I used `04_lock_monitor.sql` (`pg_stat_activity` / `pg_blocking_pids`) to see which session was blocking, released it with ROLLBACK, and then retried. `v_balance_reconciliation` then flagged account 3010000005 (stored N1,499,000 against a ledger total of N1,500,000), because the committed UPDATE had changed the balance without a ledger line. Step 5.3 restored the balance from the ledger. This shows why money should only move through `fn_transfer`, which always writes the ledger lines inside one transaction, and why a reconciliation check is valuable.

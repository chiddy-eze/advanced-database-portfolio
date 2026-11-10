# Portfolio 5 – Distributed and Cloud Database Exercise

**Case study:** Otigba MFB (simulated digital microfinance bank), same data as Portfolios 1–4
**Platform:** MongoDB Atlas, the managed cloud database service (cluster `otigba-cluster`, free M0 tier, AWS Paris eu-west-3), accessed from MongoDB Compass / mongosh

## 1. Aim

To deploy part of Otigba MFB's data on a **real cloud database**, show with evidence how it is **replicated** across several servers, measure how **consistency settings** affect it, and design how the bank would **scale (sharding)** and **stay available**. The ledger stays on PostgreSQL, and its distribution is discussed in section 6.

## 2. Cloud deployment

| Item | Otigba MFB set-up |
|---|---|
| Service model | **Database-as-a-Service** (managed). Atlas runs the servers, patching, replication and monitoring |
| Provider / region | AWS, Paris (eu-west-3) |
| Tier | M0 free: a shared cluster, 512 MB storage |
| Topology | **Replica set of 3 members** (1 primary + 2 secondaries), created automatically |
| Network security | **IP access list**: only my current IP address may connect (no `0.0.0.0/0`) |
| Authentication | A dedicated database user (`chiddyeze_db_user`). The password was **rotated** after it appeared in a screenshot |
| Encryption | TLS in transit is enforced by Atlas (the `mongodb+srv://` connection). Storage is encrypted at rest by default |

**Production note:** the auto-created user has the *Atlas Admin* role. In production, the application would get a user with only `readWrite` on `otigba_mfb`, which applies the principle of least privilege.

Evidence: `p5_01_atlas_cluster_overview.png`, `p5_02_network_access.png`.

## 3. Replication (BLOCK 1)

`db.hello()` shows the replica set name, its **3 member hosts**, which one is the **primary**, and that my session is connected to it. Every write goes to the primary, is recorded in its **oplog** (operations log), and is copied to the two secondaries. If the primary fails, the secondaries hold an **election** and one becomes the new primary automatically, usually within seconds. The drivers' **retryable writes** resend a write that was interrupted by the switch.

> The free tier does not allow a manual failover test ("Test Resilience" is only available on dedicated tiers), so failover is explained here rather than demonstrated.

## 4. Consistency vs latency (BLOCKS 2–4)

| Setting | Meaning | Result on my cluster |
|---|---|---|
| Write concern `w:1` | Only the primary confirms | avg **162 ms** per insert (20 inserts) |
| Write concern `w:"majority"` | 2 of 3 servers confirm | avg **164 ms** per insert (20 inserts) |
| Read preference `primary` | Read the latest data from the primary | host: `ac-lgotnak-shard-00-02` (primary) |
| Read preference `secondaryPreferred` | Read from a copy, which may be slightly behind | host: `ac-lgotnak-shard-00-01` (a secondary, a different server ✓) |
| Read concern `majority` | Only return data that can never be rolled back | same rows returned as `local` (40 documents) |

**Interpretation.** On my connection, `w:"majority"` was only about **2 ms slower** than `w:1` (164 vs 162 ms). Almost all of the ~160 ms is the network round trip from Lagos to the Paris data centre. The extra wait for a secondary to confirm happens inside AWS's fast internal network, so it adds very little. This means Otigba MFB can use the safer `w:"majority"` for important writes at almost no cost in speed. Choosing a region closer to Nigeria would cut the ~160 ms itself.

BLOCK 3 shows that the **primary is `shard-00-02`**. With `secondaryPreferred`, the same read was answered by **`shard-00-01`**, a different server holding a copy. This proves that reads can be spread across the replicas. The trade-off is that a secondary may be slightly behind the primary (eventual consistency).

**Choices for Otigba MFB:**

| Data | Write concern | Read preference / concern | Why |
|---|---|---|---|
| Profile/KYC updates | `majority` | `primary` | A customer must see their own change immediately |
| App activity feed, notifications | `majority` | `secondaryPreferred` | A few seconds' delay is acceptable, and it offloads the primary |
| OTP codes | `majority` | `primary` | An OTP must be readable the moment it is sent |

## 5. CAP / PACELC analysis

The CAP theorem says that during a network **P**artition a distributed system must choose **C**onsistency or **A**vailability. PACELC adds that **E**lse, in normal operation, it trades **L**atency against **C**onsistency.

| Component | During a partition | Normal operation | Justification |
|---|---|---|---|
| **Ledger (PostgreSQL + synchronous standby)** | **CP**: refuse transfers rather than risk a double spend | Consistency over latency (synchronous commit) | A wrong balance is worse than a short outage |
| **MongoDB primary with `w:majority`** | **CP**: only the side holding a majority can elect a primary and accept writes | Consistency over latency | No confirmed write can be lost |
| **MongoDB reads from secondaries** | Stays **A**vailable for reads | Latency over consistency | Feeds and statistics tolerate staleness |

## 6. Scaling out: sharding design

Replication copies **all** the data to every server, which improves availability and read capacity. **Sharding** splits the data **across** servers so that each holds only part of it, which scales writes and storage. The M0 tier is not sharded (BLOCK 5 confirms this: sharding needs a dedicated M30+ cluster), so here is the design Otigba MFB would use as it grows.

**Shard key options for `transactions`:**

| Shard key | Distribution | Statement query (one account) | Verdict |
|---|---|---|---|
| `{ created_at: 1 }` | **Hot shard**: every new transaction goes to the last shard | Scatter-gather | ✗ |
| `{ _id: "hashed" }` | Even | **Scatter-gather** (asks every shard) | △ |
| `{ payer_account: 1, created_at: 1 }` | Even across ~549k+ accounts, with high cardinality | **Targeted** to one shard, already in date order | **✓ chosen** |

Note: `legs.account_number` is an array, and **array fields cannot be shard keys**. The design therefore adds a top-level `payer_account` field. For `customers`, the key would be `{ _id: "hashed" }`, giving an even spread and targeted look-ups by customer ID.

**Zone sharding** could pin a group of customers' data to a chosen region, for example servers inside Nigeria, which helps with data-residency requirements and latency.

**PostgreSQL ledger:** sharding the ledger is avoided for as long as possible, because a transfer between accounts on two different shards would need a slower, more complex **distributed transaction** (two-phase commit). The ledger scales instead by:

- a **synchronous standby** in another availability zone, for failover with zero data loss
- an **asynchronous read replica** for reports. Portfolio 2's Q4 analytics query would run there, not on the primary
- **monthly partitioning** of `ledger_entries`, so old months can be archived and queries on recent data scan less

The full design is in [`architecture.png`](architecture.png) (source: `architecture.mmd`).

## 7. Limitations of this exercise

- **M0 is a shared, free tier.** There is no manual failover test, no sharding, no backups and limited metrics. The replication evidence is real; the failover and sharding parts are designed and explained, not run.
- **Latency figures depend on my internet connection** to Paris. A production deployment would choose a region closer to Nigerian users (for example, AWS Cape Town) and connect from servers in the same region.

## 8. How to run

1. Atlas web UI: take the screenshots `p5_01` (cluster overview showing tier, region and "Replica Set – 3 nodes") and `p5_02` (Security → Network Access).
2. Compass → `>_ MONGOSH` → `use otigba_mfb`, then paste each **BLOCK** of `01_replication_consistency.js` one at a time.
3. Fill in the blanks in section 4 with your own results.

## 9. Evidence (`screenshots/`)

| # | File | Shows |
|---|---|---|
| 01 | `p5_01_atlas_cluster_overview.png` | Atlas: tier, provider/region, replica set |
| 02 | `p5_02_network_access.png` | IP access list (only my IP) |
| 03 | `p5_03_replica_set_members.png` | 3 members, the primary, and my connection |
| 04 | `p5_04_write_concern_timing.png` | w:1 vs w:majority |
| 05 | `p5_05_read_preference.png` | Primary vs secondary host |
| 06 | `p5_06_read_concern.png` | local vs majority read concern |
| 07 | `p5_07_sharding_check.png` | Not sharded (M0) |


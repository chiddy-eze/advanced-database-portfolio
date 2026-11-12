# Advanced Database Systems Portfolio – Otigba MFB

**Course:** MIT 8103 Advanced Database Systems · MIVA Open University · 2026/2027 First Semester CA
**Student:** Ezeonwumere Chidiebere · **Student ID:** 301923965
**Repository:** https://github.com/chiddy-eze/advanced-database-portfolio

---

## Selected case study: Otigba MFB (simulated)

**Otigba MFB** is a fictitious Nigerian **digital microfinance bank**. Customers open savings and current accounts, verify their identity (BVN and KYC tiers), and move money through a **mobile app, USSD, POS terminals, the web and branches**.

| | |
|---|---|
| **Database users** | Customers (through the app), customer-support officers, operations staff (reversals), compliance/audit officers, data analysts |
| **Major data** | Branches, customers & KYC, account types, accounts & balances, transactions, double-entry ledger lines, audit trail, OTP sessions, channel metadata |
| **Key operations** | Open accounts, deposit, transfer funds, reverse failed or disputed transfers, view statements, audit balances against the ledger, report by channel |

A simulated organisation was chosen deliberately. I work in a fintech, and using a real institution's name or data would raise confidentiality issues. **All names, BVNs, phone numbers and amounts in this repository are invented.** The same case study is used in all five activities.

## Portfolio contents

| # | Folder | Activity | Highlights |
|---|---|---|---|
| 1 | [`portfolio-1-database-design`](portfolio-1-database-design) | Database Design & Modelling | 7-table 3NF schema, ER diagram, keys & CHECK constraints, audit trigger, normalisation walkthrough |
| 2 | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation) | Query Processing & Optimisation | 230k transactions / 414k ledger lines, `EXPLAIN ANALYZE` before/after, composite, partial, expression and covering indexes (up to **1,163× faster**) |
| 3 | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency) | Transactions & Concurrency | ACID transfer function, COMMIT/ROLLBACK/SAVEPOINT, lost update reproduced and fixed (`FOR UPDATE`, `REPEATABLE READ`), lock monitoring, reconciliation |
| 4 | [`portfolio-4-nosql`](portfolio-4-nosql) | NoSQL & Advanced Data Models | MongoDB document model (embed vs reference), `$jsonSchema` validation, aggregation & `$lookup`, geospatial query, multi-document ACID transaction, key-value OTP with TTL |
| 5 | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud) | Distributed & Cloud Database | MongoDB Atlas 3-node replica set, write/read concern and read-preference tests, CAP/PACELC analysis, shard-key design, target architecture |

Each folder has its own **README** (what was done, how to run it, results and analysis), the **scripts**, and a **`screenshots/`** folder of evidence.

## Technology

| Purpose | Tool |
|---|---|
| Relational DBMS | PostgreSQL 18 (scripts are compatible with 16+) with pgAdmin 4 |
| NoSQL / cloud | MongoDB Atlas (M0, AWS Paris eu-west-3, MongoDB 8.0) with MongoDB Compass / mongosh |
| Diagrams | Mermaid (`.mmd` source files plus rendered `.png`) |
| Data generation | SQL `generate_series()` (Portfolio 2), Python 3 (Portfolio 4) |
| Version control | Git / GitHub |

## Key results

| Area | Result |
|---|---|
| Integrity | 6 of 6 invalid inserts/updates rejected by keys and CHECK constraints |
| Performance | Statement query 195.358 ms → 0.168 ms. Failed-transfer search 67.267 ms → 0.175 ms |
| Concurrency | Lost update reproduced (N40,000 instead of N30,000), then prevented by row locking and by REPEATABLE READ (N30,000) |
| Audit | The reconciliation view detected a real N1,000 balance/ledger mismatch, which was then repaired |
| Replication | 3 members confirmed. `w:"majority"` 164 ms vs `w:1` 162 ms. Reads served by a different server under `secondaryPreferred` |

## How to reproduce

1. Install PostgreSQL + pgAdmin and create a database `otigba_mfb`. Run the Portfolio 1, 2 and 3 scripts **in folder order**, following each README.
2. Create a free MongoDB Atlas cluster and connect with Compass. Run Portfolio 4 (`01_setup_collections.js`, then import `data/*.json`, then `02_queries_and_demos.js`), then Portfolio 5.

## Academic integrity and AI-use declaration

- **AI tool used:** Claude, I used it through the browser.
- **What it was used for:** explaining concepts; drafting the SQL/JavaScript scripts, the data generator and the README text; troubleshooting errors I hit (the pgAdmin VACUUM transaction error, the stuck lock wait, MongoDB connection and authentication errors); and structuring the documentation.
- **How I checked the output:** I ran every script myself in pgAdmin and MongoDB Compass, captured my own screenshots and timings (all figures in this repository are from my computer and my Atlas cluster), compared each result with the expected outcome, investigated and fixed the errors that came up, and wrote the explanations and my reflection.

## References

- Abadi, D. (2012) 'Consistency tradeoffs in modern distributed database system design', *IEEE Computer*, 45(2), pp. 37–42.
- Brewer, E. (2012) 'CAP twelve years later: how the "rules" have changed', *IEEE Computer*, 45(2), pp. 23–29.
- Elmasri, R. and Navathe, S.B. (2016) *Fundamentals of Database Systems*. 7th edn. Pearson.
- Kleppmann, M. (2017) *Designing Data-Intensive Applications*. O'Reilly Media.
- MongoDB, Inc. (2026) *MongoDB Manual: Data Modeling, Replication, Read/Write Concern, Transactions, Sharding, Schema Validation*. Available at: https://www.mongodb.com/docs/manual/
- PostgreSQL Global Development Group (2026) *PostgreSQL Documentation: Indexes, Using EXPLAIN, Transaction Isolation, Explicit Locking*. Available at: https://www.postgresql.org/docs/current/
- Silberschatz, A., Korth, H.F. and Sudarshan, S. (2020) *Database System Concepts*. 7th edn. McGraw-Hill.

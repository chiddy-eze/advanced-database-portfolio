// =====================================================================
// Otigba MFB - Portfolio 4: queries, aggregations, ACID transaction, TTL
// Where: Compass ">_ MONGOSH" panel, after  use otigba_mfb
// Paste ONE BLOCK at a time (from "// ---- BLOCK n" to the next one),
// press Enter, and screenshot the result.
// =====================================================================


// ---- BLOCK 1: data loaded? flexible schema? --------------------------
({
  customers: db.customers.countDocuments(),
  transactions: db.transactions.countDocuments(),
  customers_with_business_profile: db.customers.countDocuments({ business_profile: { $exists: true } }),
  customers_with_devices: db.customers.countDocuments({ devices: { $exists: true } }),
  customers_without_devices: db.customers.countDocuments({ devices: { $exists: false } })
});
// [SCREENSHOT: p4_02_counts_flexible_schema.png]


// ---- BLOCK 2: Q1 - whole customer profile in ONE read (no JOINs) -----
db.customers.findOne({ "accounts.account_number": "3010000001" });
// [SCREENSHOT: p4_03_q1_customer_document.png]


// ---- BLOCK 3: helper to summarise an execution plan -----------------
function planSummary(ex) {
  const s = JSON.stringify(ex.queryPlanner.winningPlan);
  return {
    stages: [...new Set(s.match(/"stage":"[A-Z_]+"/g))],
    index_used: (s.match(/"indexName":"[^"]+"/) || ["none - full collection scan"])[0],
    keys_examined: ex.executionStats.totalKeysExamined,
    docs_examined: ex.executionStats.totalDocsExamined,
    docs_returned: ex.executionStats.nReturned,
    time_ms: ex.executionStats.executionTimeMillis
  };
}
print("planSummary() ready");


// ---- BLOCK 4: Q2 - account statement: WITHOUT index (forced scan) ----
planSummary(
  db.transactions.find({ "legs.account_number": "3030000123" })
    .sort({ created_at: -1 }).limit(10)
    .hint({ $natural: 1 })                 // forces a COLLSCAN for comparison
    .explain("executionStats"));
// [SCREENSHOT: p4_04_q2_plan_collscan.png]


// ---- BLOCK 5: Q2 - account statement: WITH index ix_statement ---------
planSummary(
  db.transactions.find({ "legs.account_number": "3030000123" })
    .sort({ created_at: -1 }).limit(10)
    .explain("executionStats"));
// [SCREENSHOT: p4_05_q2_plan_ixscan.png]

db.transactions.find(
  { "legs.account_number": "3030000123" },
  { amount: 1, channel: 1, status: 1, created_at: 1, "legs.direction": 1, "legs.account_number": 1 })
  .sort({ created_at: -1 }).limit(5);
// [SCREENSHOT: p4_06_q2_statement_rows.png]


// ---- BLOCK 6: Q3 - aggregation: value per channel, last 30 days -------
db.transactions.aggregate([
  { $match: { type: "TRANSFER", status: "SUCCESSFUL",
              created_at: { $gte: new Date(Date.now() - 30 * 24 * 3600 * 1000) } } },
  { $group: { _id: "$channel", transfers: { $sum: 1 }, total_value: { $sum: "$amount" } } },
  { $sort: { total_value: -1 } }
]);
// [SCREENSHOT: p4_07_q3_channel_totals.png]


// ---- BLOCK 7: Q4 - top 5 senders, joined to customers with $lookup ---
db.transactions.aggregate([
  { $match: { type: "TRANSFER", status: "SUCCESSFUL" } },
  { $unwind: "$legs" },
  { $match: { "legs.direction": "DEBIT" } },
  { $group: { _id: "$legs.customer_id", total_sent: { $sum: "$amount" }, transfers: { $sum: 1 } } },
  { $sort: { total_sent: -1 } },
  { $limit: 5 },
  { $lookup: { from: "customers", localField: "_id", foreignField: "_id", as: "c" } },
  { $project: { _id: 0, customer_id: "$_id",
                name: { $concat: [ { $first: "$c.name.first" }, " ", { $first: "$c.name.last" } ] },
                kyc_tier: { $first: "$c.kyc.tier" }, transfers: 1, total_sent: 1 } }
]);
// [SCREENSHOT: p4_08_q4_top_senders.png]


// ---- BLOCK 8: Q5 - different shapes per channel (polymorphic) + geo ---
({
  pos_example:  db.transactions.findOne({ channel: "POS" },  { channel: 1, amount: 1, channel_details: 1 }),
  ussd_example: db.transactions.findOne({ channel: "USSD" }, { channel: 1, amount: 1, channel_details: 1 }),
  mobile_transfers_within_15km_of_yaba: db.transactions.countDocuments({
    "channel_details.geo": { $geoWithin: { $centerSphere: [ [3.3792, 6.5095], 15 / 6378.1 ] } } })
});
// [SCREENSHOT: p4_09_q5_polymorphic_geo.png]


// ---- BLOCK 9: helper - show the three demo balances -------------------
function showBalances() {
  return db.customers.aggregate([
    { $unwind: "$accounts" },
    { $match: { "accounts.account_number": { $in: ["3010000001", "3010000003", "3010000006"] } } },
    { $project: { _id: 0, account: "$accounts.account_number", owner: "$name.first", balance: "$accounts.balance" } },
    { $sort: { account: 1 } }
  ]).toArray();
}
showBalances();
// Expected: 3010000001 Adaeze 250000.00 | 3010000003 Tunde 900000.00 | 3010000006 Funmi 15000.00
// [SCREENSHOT: p4_10_balances_before.png]


// ---- BLOCK 10: multi-document ACID transaction that COMMITS ----------
// Adaeze sends N25,000 to Tunde: 2 customer documents + 1 transaction document
var session = db.getMongo().startSession();
var sdb = session.getDatabase("otigba_mfb");
session.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
try {
  const debit = sdb.customers.updateOne(
    { accounts: { $elemMatch: { account_number: "3010000001", status: "ACTIVE", balance: { $gte: NumberDecimal("25000.00") } } } },
    { $inc: { "accounts.$.balance": NumberDecimal("-25000.00") } });
  if (debit.modifiedCount !== 1) throw new Error("Insufficient funds or inactive account");
  sdb.customers.updateOne(
    { "accounts.account_number": "3010000003" },
    { $inc: { "accounts.$.balance": NumberDecimal("25000.00") } });
  sdb.transactions.insertOne({
    _id: "MDB-TRF-0001", type: "TRANSFER", amount: NumberDecimal("25000.00"), currency: "NGN",
    status: "SUCCESSFUL", channel: "MOBILE", created_at: new Date(), narration: "MongoDB ACID demo",
    legs: [ { account_number: "3010000001", customer_id: "CUS-000001", direction: "DEBIT" },
            { account_number: "3010000003", customer_id: "CUS-000002", direction: "CREDIT" } ] });
  session.commitTransaction();
  print("COMMITTED: N25,000 moved from Adaeze to Tunde");
} catch (e) {
  session.abortTransaction();
  print("ABORTED: " + e.message);
} finally {
  session.endSession();
}
showBalances();
// Expected: Adaeze 225000.00, Tunde 925000.00
// [SCREENSHOT: p4_11_transaction_committed.png]


// ---- BLOCK 11: multi-document transaction that ABORTS (atomicity) -----
// Tunde is CREDITED first, then Funmi's debit of N20,000 fails (she has N15,000).
var session = db.getMongo().startSession();
var sdb = session.getDatabase("otigba_mfb");
session.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
try {
  sdb.customers.updateOne(
    { "accounts.account_number": "3010000003" },
    { $inc: { "accounts.$.balance": NumberDecimal("20000.00") } });
  print("Step 1: Tunde credited N20,000 (inside the transaction, not yet committed)");
  const debit = sdb.customers.updateOne(
    { accounts: { $elemMatch: { account_number: "3010000006", status: "ACTIVE", balance: { $gte: NumberDecimal("20000.00") } } } },
    { $inc: { "accounts.$.balance": NumberDecimal("-20000.00") } });
  if (debit.modifiedCount !== 1) throw new Error("Insufficient funds: Funmi cannot send N20,000");
  session.commitTransaction();
  print("COMMITTED");
} catch (e) {
  session.abortTransaction();
  print("ABORTED: " + e.message + " - Tunde's credit was undone too");
} finally {
  session.endSession();
}
showBalances();
// Expected: Tunde still 925000.00, Funmi still 15000.00
// [SCREENSHOT: p4_12_transaction_aborted.png]


// ---- BLOCK 12: validation rules reject bad data ----------------------
try {
  db.customers.insertOne({
    bvn: "12345", name: { first: "Bad", last: "Data" },
    contact: { email: "bad.data@example.com", phone: "+2340000000000" },
    kyc: { tier: 5 },
    accounts: [ { account_number: "3099999999", type: "SAV_T1", balance: NumberDecimal("-10.00"), status: "ACTIVE" } ],
    created_at: new Date() });
} catch (e) { print("REJECTED: " + e.message); }

try {
  db.customers.insertOne({
    bvn: "22100000001", name: { first: "Copy", last: "Cat" },
    contact: { email: "copy.cat@example.com", phone: "+2340000000001" },
    kyc: { tier: 1 },
    accounts: [ { account_number: "3099999998", type: "SAV_T1", balance: NumberDecimal("0.00"), status: "ACTIVE" } ],
    created_at: new Date() });
} catch (e) { print("REJECTED: " + e.message); }
// Expected: "Document failed validation" and "E11000 duplicate key error ... ux_bvn"
// [SCREENSHOT: p4_13_validation_errors.png]


// ---- BLOCK 13: key-value pattern with automatic expiry (TTL) ----------
db.otp_sessions.insertOne({ _id: "otp:+2348030000001", code: "482913",
                            purpose: "TRANSFER_AUTH", created_at: new Date() });
({
  lookup_by_key: db.otp_sessions.findOne({ _id: "otp:+2348030000001" }),
  ttl_index: db.otp_sessions.getIndexes().find(i => i.name === "ttl_5_minutes")
});
// [SCREENSHOT: p4_14_ttl_otp_created.png]
// Wait about 6 minutes, then run ONLY the next line - the OTP has disappeared (null):
db.otp_sessions.findOne({ _id: "otp:+2348030000001" });
// [SCREENSHOT: p4_15_ttl_otp_expired.png]


// ---- BLOCK 14: audit - embedded balances vs transaction history -------
var mismatches = db.transactions.aggregate([
  { $match: { status: "SUCCESSFUL" } },
  { $unwind: "$legs" },
  { $group: { _id: "$legs.account_number",
              ledger: { $sum: { $cond: [ { $eq: ["$legs.direction", "CREDIT"] }, "$amount", { $multiply: ["$amount", -1] } ] } } } },
  { $lookup: { from: "customers", localField: "_id", foreignField: "accounts.account_number", as: "c" } },
  { $project: { ledger: 1,
                stored: { $first: { $map: {
                  input: { $filter: { input: { $first: "$c.accounts" }, cond: { $eq: ["$$this.account_number", "$_id"] } } },
                  in: "$$this.balance" } } } } },
  { $match: { $expr: { $ne: ["$stored", "$ledger"] } } }
]).toArray();
print("Accounts whose stored balance does not match their transactions: " + mismatches.length);
mismatches;
// Expected: 0
// [SCREENSHOT: p4_16_reconciliation.png]

// =====================================================================
// Otigba MFB - Portfolio 4: MongoDB collections, validation rules, indexes
// Where: MongoDB Compass -> connect to otigba-cluster -> ">_ MONGOSH" panel
// First type:   use otigba_mfb      (press Enter)
// Then paste this WHOLE file and press Enter.
// =====================================================================

// Start clean (safe to re-run)
db.customers.drop();
db.transactions.drop();
db.otp_sessions.drop();

// ---------------------------------------------------------------------
// 1. CUSTOMERS - one document per customer, accounts EMBEDDED inside it
//    $jsonSchema = MongoDB's equivalent of NOT NULL / CHECK constraints
// ---------------------------------------------------------------------
db.createCollection("customers", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["bvn", "name", "contact", "kyc", "accounts", "created_at"],
    properties: {
      bvn:     { bsonType: "string", pattern: "^[0-9]{11}$", description: "11-digit BVN" },
      name:    { bsonType: "object", required: ["first", "last"] },
      contact: { bsonType: "object", required: ["email", "phone"] },
      kyc:     { bsonType: "object", required: ["tier"],
                 properties: { tier: { bsonType: "number", minimum: 1, maximum: 3 } } },
      accounts: {
        bsonType: "array", minItems: 1,
        items: {
          bsonType: "object",
          required: ["account_number", "type", "balance", "status"],
          properties: {
            account_number: { bsonType: "string", pattern: "^[0-9]{10}$" },
            type:    { enum: ["SAV_T1", "SAV_T3", "CURRENT", "TARGET"] },
            balance: { bsonType: "decimal", minimum: 0, description: "Decimal128, never negative" },
            status:  { enum: ["ACTIVE", "FROZEN", "CLOSED"] }
          }
        }
      },
      created_at: { bsonType: "date" }
    }
  } },
  validationAction: "error"
});

// ---------------------------------------------------------------------
// 2. TRANSACTIONS - separate collection (grows without limit, so it is
//    REFERENCED by account number, not embedded in the customer)
// ---------------------------------------------------------------------
db.createCollection("transactions", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["type", "amount", "status", "channel", "created_at", "legs"],
    properties: {
      type:    { enum: ["DEPOSIT", "WITHDRAWAL", "TRANSFER", "REVERSAL"] },
      amount:  { bsonType: "decimal", minimum: 0.01 },
      status:  { enum: ["PENDING", "SUCCESSFUL", "FAILED", "REVERSED"] },
      channel: { enum: ["MOBILE", "USSD", "POS", "WEB", "BRANCH"] },
      created_at: { bsonType: "date" },
      legs: {
        bsonType: "array", minItems: 1,
        items: { bsonType: "object", required: ["account_number", "direction"],
                 properties: { direction: { enum: ["DEBIT", "CREDIT"] } } }
      }
    }
  } },
  validationAction: "error"
});

// ---------------------------------------------------------------------
// 3. OTP_SESSIONS - key-value style: look up by key, expires automatically
// ---------------------------------------------------------------------
db.createCollection("otp_sessions");

// ---------------------------------------------------------------------
// 4. INDEXES
// ---------------------------------------------------------------------
db.customers.createIndex({ bvn: 1 }, { unique: true, name: "ux_bvn" });
db.customers.createIndex({ "accounts.account_number": 1 }, { unique: true, name: "ux_account_number" }); // multikey
db.customers.createIndex({ "contact.email": 1 }, { unique: true, name: "ux_email" });

db.transactions.createIndex({ "legs.account_number": 1, created_at: -1 }, { name: "ix_statement" });       // statement
db.transactions.createIndex({ status: 1, created_at: -1 }, { name: "ix_status_date" });                     // reporting
db.transactions.createIndex({ "channel_details.geo": "2dsphere" }, { name: "ix_geo" });                     // location

db.otp_sessions.createIndex({ created_at: 1 }, { expireAfterSeconds: 300, name: "ttl_5_minutes" });          // TTL

// Evidence for the screenshot
({
  collections: db.getCollectionNames(),
  customer_indexes: db.customers.getIndexes().map(i => i.name),
  transaction_indexes: db.transactions.getIndexes().map(i => i.name),
  otp_indexes: db.otp_sessions.getIndexes().map(i => i.name)
});

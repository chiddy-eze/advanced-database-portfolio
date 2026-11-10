// =====================================================================
// Otigba MFB - Portfolio 5: replication, consistency and availability
// evidence from the MongoDB Atlas cluster (otigba-cluster, M0, 3 nodes)
// Where: Compass ">_ MONGOSH" panel, after  use otigba_mfb
// Paste ONE BLOCK at a time, press Enter, screenshot the result.
// =====================================================================


// ---- BLOCK 1: the replica set - 3 copies of the data on 3 servers ----
var h = db.hello();
({
  replica_set_name: h.setName,
  members: h.hosts,                       // the 3 servers holding a full copy
  current_primary: h.primary,             // the ONE server that accepts writes
  connected_to: h.me,
  i_am_writable_primary: h.isWritablePrimary,
  mongodb_version: db.version()
});
// [SCREENSHOT: p5_03_replica_set_members.png]


// ---- BLOCK 2: write concern - how many servers must confirm a write? --
// w:1          -> primary only (fast, but lost if the primary dies before copying)
// w:"majority" -> 2 of 3 servers (survives the loss of any one server)
db.repl_test.drop();
function timeWrites(wc, n) {
  var start = Date.now();
  for (var i = 0; i < n; i++) {
    db.repl_test.insertOne({ test: JSON.stringify(wc), i: i, at: new Date() }, { writeConcern: wc });
  }
  return Math.round((Date.now() - start) / n);
}
({
  avg_ms_w1:        timeWrites({ w: 1 }, 20),
  avg_ms_wmajority: timeWrites({ w: "majority", wtimeout: 5000 }, 20),
  documents_written: db.repl_test.countDocuments()
});
// Expected: both succeed; "majority" is usually a little slower (it waits for a secondary)
// [SCREENSHOT: p5_04_write_concern_timing.png]


// ---- BLOCK 3: read preference - which server answers a read? ---------
var fromPrimary = db.repl_test.find().explain().serverInfo;
db.getMongo().setReadPref("secondaryPreferred");
var fromSecondary = db.repl_test.find().explain().serverInfo;
db.getMongo().setReadPref("primary");          // back to the safe default
({
  read_with_primary:            fromPrimary.host,
  read_with_secondaryPreferred: fromSecondary.host,
  served_by_different_servers:  fromPrimary.host !== fromSecondary.host
});
// Expected: two different host names -> reads can be spread across replicas
// [SCREENSHOT: p5_05_read_preference.png]


// ---- BLOCK 4: read concern - how "committed" must data be to be read? -
({
  local_read_count: db.runCommand({ find: "repl_test", filter: {}, readConcern: { level: "local" } })
                      .cursor.firstBatch.length,
  majority_read_count: db.runCommand({ find: "repl_test", filter: {}, readConcern: { level: "majority" } })
                      .cursor.firstBatch.length,
  note: "majority = only data acknowledged by 2 of 3 nodes; it can never be rolled back after a failover"
});
// [SCREENSHOT: p5_06_read_concern.png]


// ---- BLOCK 5: is this cluster sharded? -------------------------------
try {
  printjson(db.adminCommand({ listShards: 1 }));
} catch (e) {
  print("Not sharded: " + e.message);
  print("The free M0 tier is a single replica set. Sharding needs a dedicated tier (M30+). See README section 5 for the shard-key design.");
}
// [SCREENSHOT: p5_07_sharding_check.png]


// ---- BLOCK 6: tidy up -----------------------------------------------
db.repl_test.drop();

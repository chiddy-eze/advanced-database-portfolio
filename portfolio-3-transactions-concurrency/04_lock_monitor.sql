-- =====================================================================
-- Otigba MFB - Portfolio 3: LOCK MONITOR (Query Tool tab 3)
-- Step 2.5: run this while Session B is waiting.
-- It shows which session is waiting and which session is blocking it.
-- =====================================================================
SELECT pid,
       state,
       wait_event_type,
       pg_blocking_pids(pid)  AS blocked_by_pid,
       now() - xact_start     AS transaction_open_for,
       left(query, 70)        AS last_query
FROM pg_stat_activity
WHERE datname = 'otigba_mfb'
  AND pid <> pg_backend_pid()
  AND state <> 'idle'
ORDER BY pid;
-- Expected: Session B -> state 'active', wait_event_type 'Lock', blocked_by_pid = {Session A's pid}
--           Session A -> state 'idle in transaction' (holding the row lock)   [SCREENSHOT: p3_16_s2_lock_monitor.png]

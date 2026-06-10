# V0.09 execution spec (one page)

ENGINE STATE:
  Graph G (nodes + edges)
  PendingRequests: Queue<Request>
  Tick counter T
  MatchIndex: incremental match registry (for incremental matching)
  EventLog: append-only Event nodes

TICK LOOP:
  function tick():
    // PHASE 1: COLLECT
    Matches = []
    for each active Rule R:
      if circuit_breaker(R) is OPEN: continue
      if rate_limit_exceeded(R): continue
      M = incremental_match(R.match, G)
      for each match m in M:
        m.rule = R
        m.creation_tick = m.creation_tick or T
        m.age = T - m.creation_tick
        m.baseScore = R.priority * 1000 + dynamicScore(m)
        Matches.append(m)

    // PHASE 2: SCORE & SELECT (fair, deterministic)
    for m in Matches:
      m.score = m.baseScore + floor(m.age / AGE_BOOST_INTERVAL) * AGE_BOOST_VALUE

    // Group by priority band and round-robin to avoid starvation
    bands = group_by(Matches, band_of(m.score))
    selected = []
    locked_nodes = set()
    band_order = deterministic_order(bands.keys)
    band_cursor = 0
    no_progress_rounds = 0

    while not all_bands_exhausted and no_progress_rounds < MAX_BAND_ROUNDS:
      band = band_order[band_cursor]
      candidates = sort(bands[band], by = (-m.score, m.creation_tick, m.rule.id))
      progress = false
      for m in candidates:
        if intersects(m.write_set, locked_nodes): continue
        if conservative_read_write_conflict(m, locked_nodes): continue
        selected.append(m)
        locked_nodes = locked_nodes ? m.write_set
        progress = true
      if not progress: no_progress_rounds += 1
      band_cursor = (band_cursor + 1) % len(band_order)

    // PHASE 3: APPLY TRANSACTIONS (parallel non-conflicting)
    parallel_for each m in selected ordered by (m.score desc, m.creation_tick asc):
      lock_nodes_in_canonical_order(m.write_set)
      try:
        start_timer(m.rule.timeout_ms)
        snapshot = capture_read_snapshot(m.read_set)
        G' = apply_rewrite_atomically(m.rewrite, G, snapshot)
        if schema_valid(G'):
          commit(G')
          emit_event("TRANSACTION_COMMIT", m)
        else:
          rollback()
          emit_event("SCHEMA_VIOLATION", m)
      catch LockTimeout:
        rollback()
        emit_event("LOCK_TIMEOUT", m)
        reschedule(m)  # increment age, possibly backoff
      catch RuleTimeout:
        rollback()
        emit_event("RULE_TIMEOUT", m)
        handle_rule_timeout(m)  # engine policy: retry/escalate
      finally:
        release_locks(m.write_set)

    // PHASE 4: EMIT EVENTS & HOUSEKEEPING
    for each transaction t committed:
      create Event node with rule_id, trace_id, match_snapshot, writes_snapshot, timestamp
    process_pending_request_results()  # external workers inject ToolResult/PlanningResult nodes
    run_timeout_enforcement()  # engine marks stale requests failed
    if T % CHECKPOINT_INTERVAL == 0: checkpoint(G, PendingRequests, T)
    T += 1

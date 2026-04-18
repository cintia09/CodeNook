# orchestrator-tick — Advance one task one phase

**Role**: Core tick function that advances task state machine.

**Exit codes**:
- 0: changed (dispatch succeeded, state advanced)
- 1: blocked (preflight failed, iteration limit, HITL gate)
- 2: usage error (missing args, task not found)
- 3: idle (terminal phase, waiting for fanout)

**CLI**:
```bash
tick.sh --task <T-NNN> [--workspace <dir>] [--dry-run]
```

**Algorithm**:
1. Run preflight checks (via preflight.sh)
2. Check iteration limit (iteration < total_iterations)
3. Check terminal phase (done → exit 3)
4. Build dispatch payload (≤500 chars)
5. Call dispatch-audit to log the dispatch
6. Invoke $CODENOOK_DISPATCH_CMD (default: stub)
7. On success: increment iteration, append tick_log entry
8. On failure: rollback state, exit non-zero

**Dispatch stub**: If CODENOOK_DISPATCH_CMD not set, uses internal stub that writes success JSON to $CODENOOK_DISPATCH_SUMMARY.

**State updates**:
- `.iteration` increments on successful dispatch
- `.tick_log[]` appends `{ts, action, result}`

→ Design basis: architecture-v6.md §3.1.3 (orchestrator-tick algorithm)

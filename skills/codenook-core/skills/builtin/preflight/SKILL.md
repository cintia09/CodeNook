# preflight — Pre-tick sanity check

**Role**: Validates task state before orchestrator-tick proceeds.

**Exit codes**:
- 0: ready to tick
- 1: blocked (stderr reasons)
- 2: usage error

**CLI**:
```bash
preflight.sh --task <T-NNN> [--workspace <dir>] [--json]
```

**Checks**:
1. Task directory exists
2. Task state.json is valid
3. dual_mode is set if total_iterations > 1
4. Phase is known (start, implement, test, review, distill, accept, done)
5. No blocking HITL queue entries for this task
6. Config overrides are valid (no unknown keys)

**JSON output** (when --json):
```json
{
  "ok": true|false,
  "task": "T-NNN",
  "phase": "start",
  "reasons": ["sorted", "deduped", "reason", "strings"]
}
```

→ Design basis: architecture.md §3.1.3 (orchestrator-tick prerequisites)

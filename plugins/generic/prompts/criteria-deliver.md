# Acceptance Criteria -- Deliver Phase (generic)

The deliverer's output is the user-facing artefact. Grade each:
- pass / fail / partial.

## Critical Criteria

### C1. Final answer block
The body contains a `Final answer:` block with the artefact verbatim.

### C2. Coverage
Every acceptance criterion listed by the clarifier is addressed (pass /
fail / out-of-scope) in a short audit table.

### C3. Caveats listed
Any known limitation, assumption or follow-up is surfaced explicitly.

## Verdict mapping

- All Critical pass -> `verdict: ok` (task transitions to `complete`).
- Any Critical fail -> `verdict: needs_revision` (re-run deliver) OR
  `verdict: blocked` if the missing piece is upstream (executor).

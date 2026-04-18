# Acceptance Criteria -- Execute Phase (generic)

The executor's output is graded against the bullets below. Mark each:
- pass    -- criterion fully satisfied
- fail    -- criterion violated
- partial -- partially satisfied with caveats

## Critical Criteria (any fail -> verdict: needs_revision)

### C1. Plan adherence
Every step in the analyzer's ordered plan is addressed (or the omission
is explicitly justified in the body).

### C2. Artefact present
The body contains the actual artefact (text, summary, list, snippet)
in a clearly labelled block, not merely a description of it.

### C3. Sources cited
Any external fact / source / file referenced is cited inline (URL or
relative file path) so the deliverer can audit it.

## Advisory Criteria

### A1. Length boundary
Body <= 800 lines. Above that, propose a follow-up split.

### A2. No hidden side effects
The executor only writes its own output file; no edits outside the
task `outputs/` directory.

## Output

Begin the file with YAML frontmatter:

```
---
verdict: ok | needs_revision | blocked
summary: <=200 chars
---
```

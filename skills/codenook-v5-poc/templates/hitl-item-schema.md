---
task_id: <T-xxx>
phase: <clarify|design|plan|implement|test|accept|validate>
queued_at: <ISO-8601 UTC timestamp>
reason: <short machine tag, e.g. clarity_verdict:needs_user_input>
source: <role that triggered, e.g. clarifier | validator | test-retry-exhausted | accept-conditional-2 | planner-too-complex>
priority: <low|normal|high>
options:
  - id: A
    label: <human-readable label, ≤ 60 chars>
    next_action: <advance_phase | restart_phase | decompose | mark_abandoned | apply_user_note>
  - id: B
    label: ...
    next_action: ...
default: <option id of recommended default, or null>
---

# HITL Decision Needed

## Task Context
- Task: <T-xxx — one-line goal>
- Phase: <phase name and iteration if applicable>

## What Happened
<2–5 lines: which agent returned what verdict, why this needs human judgment.
No long output dumps. Reference files by path instead.>

## Reference Files
- `.codenook/tasks/<T-xxx>/outputs/<...>.md`
- `.codenook/tasks/<T-xxx>/<subpath>/<...>.md`

## Options
<Reiterate the frontmatter options with one-line rationale each.>

- **A — <label>**: <why this might be right>
- **B — <label>**: <why this might be right>
- **C — <label>**: <why this might be right>

## Suggested Default
<Either a single option id from above, or "no default — please choose".>

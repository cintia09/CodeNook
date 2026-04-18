# session-resume — ≤500-byte state summary for new sessions

**Role**: First skill called by main session in `codenook-shell.md` after
`/clear` or new-session bootstrap. Reads workspace state and returns a
compact summary so main session can ask "Continue T-007 (implement)?".

## CLI

```bash
resume.sh [--workspace <dir>] [--json]
```

## Output (`--json`, ≤500 bytes UTF-8)

```json
{
  "active_tasks": [
    {"task_id","plugin","phase","status","last_event_ts","one_liner"}
  ],
  "current_focus": "T-NNN" | null,
  "last_session_summary": "<≤300 char tail of history/sessions/latest.md>",
  "suggested_next": "Continue T-NNN (<phase>)?" | "N active tasks — pick one?" | "No active task, awaiting user input"
}
```

The output also exposes M1-compat keys (`active_task`, `phase`,
`iteration`, `summary`, `hitl_pending`, `next_suggested_action`,
`last_action_ts`, `total_iterations`) chosen from the most-recent
task. These are part of the same 500-byte budget; under multi-task
CJK pressure the chattiest of these are dropped first (see
`_resume.py:truncate_to_bytes`).

## Algorithm (M4)

1. Read `.codenook/state.json` → `active_tasks[]`, `current_focus`.
2. For each `tid` in `active_tasks`, read
   `.codenook/tasks/<tid>/state.json` and project to the active-task
   shape above (`last_event_ts` = last `history[]` ts or `created_at`).
3. `last_session_summary = tail(history/sessions/latest.md, 300 chars)`.
4. Pick `suggested_next` based on whether `current_focus` matches an
   `in_progress` task, else by count.
5. Truncate the JSON until UTF-8 size ≤500 bytes (drops in priority
   order: tail → one_liner → per-entry secondary fields → legacy
   chatty keys).

## Backward compat (M1)

When `.codenook/state.json` does not exist, falls back to the legacy
M1 behaviour: scan every `tasks/*/state.json`, exclude `phase==done`
or `status ∈ {done,cancelled}`, sort by `updated_at` descending. The
M1 bats suite (10 tests) continues to pass.

→ Design basis: implementation-v6.md §3.4, architecture-v6.md §3.1.4

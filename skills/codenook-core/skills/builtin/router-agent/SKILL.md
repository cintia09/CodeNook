# router-agent (builtin skill — M8.2)

## Role

Per-turn entry point the main session calls to dispatch a real subagent
for **conversational task creation**. The router-agent is the SOLE
domain-aware component on the task-creation side (see
`docs/router-agent.md` §2).

This skill ships:

| File | Purpose |
|------|---------|
| `spawn.sh` | CLI entry the main session invokes once per user turn. Thin shell wrapper around `render_prompt.py`. |
| `render_prompt.py` | Deterministic context-prep + handoff helper. Acquires the per-task fcntl lock, mutates `tasks/<tid>/`, renders the system prompt, and on `--confirm` materialises `state.json` and runs the first `orchestrator-tick`. |
| `prompt.md` | Long-form system-prompt template for the spawned subagent. |
| `schemas/` | M5 YAML DSL schemas for the four canonical files (shipped in M8.1). |

## Layering reminder

`spawn.sh` does **not** call an LLM. Its job is the deterministic
context-prep + handoff envelope: it writes a fully-rendered prompt to
`tasks/<tid>/.router-prompt.md` and emits a JSON envelope that tells
the main session "go spawn a Task subagent with this prompt". The
subagent itself writes back to `router-context.md` / `router-reply.md`
/ `draft-config.yaml`; the next `spawn.sh` invocation observes the
new state.

This split keeps spawn.sh portable across host runtimes (Claude Code
Task tool, Copilot CLI task tool, plain shell) while pinning all
domain logic inside the subagent prompt.

## Inputs

| Flag | Required | Meaning |
|------|----------|---------|
| `--task-id <T-NNN>` | yes | Task id to operate on (creates `tasks/<tid>/` if absent). |
| `--workspace <path>` | yes | Workspace root. Tasks live under `<ws>/.codenook/tasks/`, plugins under `<ws>/.codenook/plugins/`. |
| `--user-turn <text>` | no | The user's latest utterance (omit on initial spawn before any user input). |
| `--user-turn-file <path>` | no | Same as `--user-turn` but read from a file (avoids shell-quoting hazards). |
| `--confirm` | no | Handoff mode: validate the current `draft-config.yaml`, materialise `state.json`, and run the first `orchestrator-tick`. |

Mutually exclusive flag groups:
* `--user-turn` and `--user-turn-file` (use one or neither).
* `--confirm` consumes the existing draft; passing `--user-turn` with
  `--confirm` is allowed (the turn is appended before validation).

## Outputs

### Files written under `tasks/<tid>/`

| File | When | Notes |
|------|------|-------|
| `router-context.md` | always (initialised on first spawn) | YAML frontmatter + chat body. |
| `draft-config.yaml` | on first spawn (empty placeholder), then by the spawned subagent | The subagent re-writes it across turns. |
| `.router-prompt.md` | every spawn | Rendered system prompt for the subagent. Read by the main session, passed to the Task tool. |
| `router-reply.md` | written by the spawned subagent (NOT by spawn.sh itself) | The main session relays this verbatim to the user. |
| `router.lock` | held during spawn.sh execution | fcntl lock; released on exit. |
| `state.json` | only on `--confirm` success | Materialised from the frozen draft. Tick reads from here onward. |

### Stdout (single JSON line)

```json
{"action": "prompt",   "task_id": "T-042", "prompt_path": "...", "context_path": "...", "reply_path": "..."}
{"action": "handoff",  "task_id": "T-042", "first_tick_status": "advanced"}
{"action": "busy",     "task_id": "T-042", "message": "router.lock held"}
{"action": "error",    "task_id": "T-042", "code": "draft_invalid", "errors": ["..."]}
```

The main session keys off `action` only.

## Side effects

* Acquires `tasks/<tid>/router.lock` (per-task fcntl, 30s timeout).
  Different task ids run in parallel; same task id serialises.
* On `--confirm` only: writes `tasks/<tid>/state.json` and invokes
  `orchestrator-tick/tick.sh --task <tid> --workspace <ws> --json`
  exactly once. No state.json is written if validation fails.

## Exit codes

| code | meaning |
|------|---------|
| 0    | success — JSON envelope on stdout describes the outcome |
| 2    | usage error (bad flags) — JSON `action: error` on stdout, human message on stderr |
| 3    | lock contention exhausted timeout — JSON `action: busy` on stdout |
| 4    | validation failure on `--confirm` — JSON `action: error` on stdout, no state mutation |

## CLI

```bash
spawn.sh --task-id T-042 --workspace ~/proj                       # initial spawn
spawn.sh --task-id T-042 --workspace ~/proj --user-turn "add Y"   # follow-up turn
spawn.sh --task-id T-042 --workspace ~/proj --confirm             # handoff
```

## See also

* `docs/router-agent.md` — canonical spec.
* `skills/builtin/_lib/router_context.py` — context I/O.
* `skills/builtin/_lib/draft_config.py` — draft validation + freeze.
* `skills/builtin/_lib/task_lock.py` — fcntl lock.

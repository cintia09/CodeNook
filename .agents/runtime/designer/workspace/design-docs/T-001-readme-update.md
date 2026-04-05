# Design Document: T-001 — Update README with Phase 2 Features

## Goal Reference
- G1: Add Hooks section
- G2: Add events.db section
- G3: Update Architecture section
- G4: Update File Structure section

## Changes Required

### G1: Add "Hooks" section (after "Goals Checklist", before "File Structure")

New section content:
```markdown
## Hooks (Agent Boundary Enforcement)

The framework uses Copilot CLI's native hook system to enforce agent boundaries
and maintain an audit trail.

### 3 Hook Types

| Hook | File | Function |
|------|------|----------|
| **session-start** | `agent-session-start.sh` | Initialize events.db, check pending messages/tasks |
| **pre-tool-use** | `agent-pre-tool-use.sh` | Enforce agent boundaries — deny unauthorized edits |
| **post-tool-use** | `agent-post-tool-use.sh` | Audit log all tool usage to events.db |

### Agent Boundary Rules

| Role | Can Edit | Cannot Edit |
|------|----------|-------------|
| 🎯 Acceptor | `.agents/` directory | Source code ⛔ |
| 🏗️ Designer | `.agents/` directory | Source code ⛔ |
| 💻 Implementer | Source code + own workspace | Other agents' workspace ⛔ |
| 🔍 Reviewer | Review reports + task board | Source code ⛔ |
| 🧪 Tester | Test files + own workspace | Source code ⛔ |

The `pre-tool-use` hook reads `.agents/runtime/active-agent` to determine
the current role, then enforces the boundary rules above. Violations are
denied with a descriptive error message.
```

### G2: Add "Audit Log (events.db)" section (after Hooks section)

```markdown
## Audit Log (events.db)

All agent actions are logged to `.agents/events.db` (SQLite) for debugging
and analysis.

### Schema

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Auto-increment primary key |
| timestamp | INTEGER | Unix timestamp (ms) |
| event_type | TEXT | session_start, tool_use, task_board_write, state_change |
| agent | TEXT | Active agent name |
| task_id | TEXT | Related task ID (if applicable) |
| tool_name | TEXT | Tool used (bash, edit, create, etc.) |
| detail | TEXT | JSON detail string |

### Querying

\```bash
# Recent events
sqlite3 .agents/events.db "SELECT * FROM events ORDER BY id DESC LIMIT 20;"

# Events by agent
sqlite3 .agents/events.db "SELECT * FROM events WHERE agent='implementer';"

# Task board changes
sqlite3 .agents/events.db "SELECT * FROM events WHERE event_type='task_board_write';"
\```
```

### G3: Update Architecture — add to Key Features list

Add these 2 items to "Key Features" section:
```markdown
- **Hook enforcement** — Agent boundaries enforced by shell hooks, not LLM self-discipline
- **SQLite audit log** — Every tool use logged to events.db for debugging and analysis
```

Update Roadmap:
```markdown
- **Phase 1** ✅ Manual role switching + FSM + task board + goals
- **Phase 2** ✅ Hooks (boundary enforcement) + events.db (audit log)
- **Phase 3** — Auto-dispatch, staleness detection, scheduled prompts
```

### G4: Update File Structure

Add hooks to global layer:
```
~/.copilot/
├── ...
├── hooks/
│   ├── hooks.json                     # Hook configuration
│   ├── agent-session-start.sh         # Session start: init events.db
│   ├── agent-pre-tool-use.sh          # Boundary enforcement
│   └── agent-post-tool-use.sh         # Audit logging
├── skills/
│   └── ...
└── agents/
    └── ...
```

Add to project layer:
```
<project>/.agents/
├── ...
├── events.db                          # SQLite audit log
└── runtime/
    ├── active-agent                   # Current active agent (for hooks)
    └── <role>/
        └── ...
```

Update Installation step list — add step for hooks:
```
4. 复制 3 个 hook 脚本到 `~/.copilot/hooks/`
5. 复制 hooks.json 配置到 `~/.copilot/hooks/`
```

## Test Specification

See `.agents/runtime/designer/workspace/test-specs/T-001-test-spec.md`

## File Impact

| File | Action | Description |
|------|--------|-------------|
| `README.md` | MODIFY | Add hooks section, events.db section, update features + roadmap + file structure + installation |

## Notes
- All content in English (README is an English document)
- Keep concise — README should be scannable, not exhaustive
- Link to hooks/ directory for detailed script docs

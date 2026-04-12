---
name: agent-memory
description: "Task memory management: Automatically saves context snapshots after each phase completes. Invoke by saying 'save memory', 'view memory', or 'task context'."
---

# Task Memory Management

## File Location
- Memory file: `<project>/.agents/memory/T-NNN-memory.json`
- One file per task, accumulating context across phases

## T-NNN-memory.json Format

```json
{
  "task_id": "T-001",
  "version": 1,
  "last_updated": "2026-04-05T12:00:00Z",
  "stages": {
    "designing": {
      "agent": "designer",
      "started_at": "2026-04-05T08:30:00Z",
      "completed_at": "2026-04-05T10:00:00Z",
      "summary": "Designed a JWT-based user authentication system with stateless architecture...",
      "decisions": ["Chose JWT over sessions because mobile support is needed", "Password hashing uses bcrypt, cost factor = 12"],
      "artifacts": [".agents/runtime/designer/workspace/design-docs/T-001-design.md"],
      "files_modified": [],
      "issues_encountered": [],
      "handoff_notes": "Implementer should complete JWT middleware first, then build login/register endpoints. Note: refresh token must be stored in httpOnly cookie."
    }
  }
}
```

## Field Descriptions

| Field | Type | Description |
|-------|------|-------------|
| `task_id` | string | Associated task ID |
| `version` | number | Optimistic lock version number |
| `last_updated` | ISO 8601 | Last update timestamp |
| `stages` | object | Memory snapshot collection keyed by phase name |

**Phase snapshot fields**: `agent` (executing role), `started_at`/`completed_at` (timestamps), `summary` (2-5 sentence summary), `decisions` (key decisions with reasons), `artifacts` (output paths), `files_modified` (source files changed), `issues_encountered` (problems), `handoff_notes` (handoff notes)

## Auto-Capture Memory

**Trigger**: FSM state transition (post-tool-use hook detects status change in task-board.json)

**Process**: Detect change → Read Agent context → Extract fields → Write to memory → Update version

**Auto-extraction**:
- `summary`: Agent summary (2-5 sentences) | `decisions`: "Chose X because Y" format
- `files_modified`: From git diff | `issues_encountered`: Problems and solutions
- `handoff_notes`: Handoff key points | `artifacts`: Output document paths

**Note**: Auto-extraction is best-effort; sensitive information is auto-redacted; memory file is auto-created if it doesn't exist

## Smart Memory Loading

Automatically loaded on Agent switch, loading only **fields relevant to the current role**:

| Downstream Role | Fields Loaded | Omitted |
|----------------|---------------|---------|
| Designer (← Acceptor) | goals, description | — |
| Implementer (← Designer) | decisions, artifacts, handoff_notes | issues_encountered |
| Reviewer (← Implementer) | files_modified, decisions, summary | handoff_notes |
| Tester (← Reviewer) | files_modified, review issues, summary | decisions |
| Acceptor (← Tester) | All stages' summary | Detailed fields |

Presented as readable text after loading (not raw JSON):
```
📝 Task Memory: T-008
🏗️ Design Phase (Designer, completed at 10:30):
  Decisions: Use post-tool-use hook to detect state changes and trigger memory save
  Handoff: Modify agent-post-tool-use.sh to add auto-capture logic
```

**Integration**: agent-switch transition → check task → read memory → filter by role → format and display

## Operations

### Save Memory (⚡ Automatically triggered on phase transition)

After state transition, the Agent **must** save memory:

1. Read `.agents/memory/T-NNN-memory.json` (create if not exists)
2. Add/update the current phase snapshot in `stages`, filling all fields
3. **🔒 Redaction** (must execute before writing):

| Sensitive Type | Match Pattern | Replace With |
|---------------|---------------|-------------|
| API Key | `AIza...`, `sk-...`, `ghp_...`, `AKIA...` | `[REDACTED:API_KEY]` |
| Password/Secret | `password=xxx`, `secret=xxx`, `token=xxx` | `[REDACTED:CREDENTIAL]` |
| Internal IP | `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x` | `[REDACTED:INTERNAL_IP]` |
| SSH/Connection String | `ssh user@host`, `mysql://user:pass@host` | `[REDACTED:CONNECTION]` |
| Environment Variable Values | Values referenced from `.env` | `[REDACTED:ENV_VALUE]` |

**Principle**: Preserve technical decisions and context, only replace secret values. When in doubt, redact.

4. version + 1, update last_updated, write to file

**Trigger timing** (corresponding state transitions):

| Transition | Saved Phase | Saved By |
|-----------|-------------|----------|
| `designing → implementing` | designing | designer |
| `implementing → reviewing` | implementing | implementer |
| `reviewing → implementing` (rejected) | reviewing | reviewer |
| `reviewing → testing` | reviewing | reviewer |
| `testing → accepting` | testing | tester |
| `testing → fixing` | testing | tester |
| `fixing → testing` | fixing | implementer |
| `accepting → accepted/accept_fail` | accepting | acceptor |
| Any → `blocked` | Current phase | Current Agent |

### Load Memory (🔄 Automatically executed when taking over a task)

Read `.agents/memory/T-NNN-memory.json`, if exists display context summary:
```
📝 Task Memory — T-001: User Authentication System
📌 Previous phase: designing (by designer), completed: 2026-04-05 10:00
   Summary: Designed a JWT-based user authentication system...
   Decisions: JWT (mobile support) / bcrypt (cost=12)
   📮 Handoff: Implementer should complete JWT middleware first, then build login/register endpoints.
```

### View Full Memory

When user says "view memory" / "task context" / "memory", display all phase memories in chronological order:
```
[1] designing — designer — 08:30 → 10:00
    Summary/decisions/artifacts/issues (one paragraph per phase)
```

### Update Memory (Append within same phase)

When significant progress occurs within the same phase: Read → Append to decisions/files_modified/issues_encountered → version+1 → Write

## Integration with Other Skills

- **agent-task-board**: State transition → FSM validation → Write to task-board → Sync Markdown → 💾 Save memory → Notify downstream
- **agent-switch**: Switch role → Check inbox → Scan tasks → 📝 Load task memory → Begin work
- **agent-events**: Memory events recorded in events.db (`memory_save` / `memory_load`)

## Notes
- Optimistic lock (version field) | Memory files **should be committed to git** (project knowledge, not temporary state)
- **🔒 Must redact before writing** | summary and handoff_notes are the most important fields — ensure high information density
- When re-entering a phase, append round information to summary

---

## Search Memory

When user says "search memory <keyword>" / "search memory <keyword>":

**Search scope**: All `.agents/memory/T-NNN-memory.json` files

| Field | Weight | Description |
|-------|--------|-------------|
| `decisions` | ⭐⭐⭐ | Past decisions and reasons |
| `issues_encountered` | ⭐⭐⭐ | Pitfalls encountered |
| `summary` | ⭐⭐ | Work summaries |
| `handoff_notes` | ⭐⭐ | Handoff experience |
| `files_modified` | ⭐ | File path changes |

**Sorting**: Exact match in decisions/issues first → Same phase type first → Most recent task first

**Context-aware**: Agent can omit keywords and auto-extract search terms from current task description/goals

**Output format**:
```
🔍 Search Memory: "redis"
[1] T-001 / implementing — issues_encountered
    "connect-redis v7 API changed, need to use new RedisStore({client})"
[2] T-003 / implementing — decisions
    "Redis cache uses ioredis for better cluster support"
```

---

## Project Summary

When user says "project summary" / "lessons learned":

Read all `T-NNN-memory.json` + `task-board.json`, aggregate and generate:
- **Architecture decisions** (extracted from designing.decisions)
- **Pitfall records** (extracted from issues_encountered)
- **Tech stack choices** (aggregated keywords from decisions)
- **File modification hotspots** (counted from files_modified)

Optionally save as `.agents/memory/PROJECT-SUMMARY.md` (overwrite update, can be committed to git)

---

## Project Memory

Cross-task persistent knowledge base. File: `<project>/.agents/memory/project-memory.json`

### Schema (canonical example)

```json
{
  "version": 1,
  "last_updated": "2026-04-10T15:00:00Z",
  "tech_stack": {
    "language": "TypeScript", "runtime": "Node.js 20", "framework": "Express.js",
    "database": "PostgreSQL + Prisma ORM", "cache": "Redis (ioredis)",
    "testing": "Vitest + Playwright", "deployment": "Docker + Caddy",
    "ci_cd": "GitHub Actions", "other": ["pnpm", "ESLint", "Prettier"]
  },
  "architecture_decisions": [
    {
      "id": "ADR-001", "title": "Choose cookie session over JWT",
      "date": "2026-04-05", "status": "accepted",
      "context": "Pure web application, no mobile support needed",
      "decision": "express-session + connect-redis",
      "consequences": "Server-side session storage required; Redis configuration needed",
      "source_task": "T-001", "superseded_by": null
    }
  ],
  "lessons_learned": [
    {
      "id": "LL-001", "date": "2026-04-05", "category": "dependency",
      "title": "connect-redis v7 API change",
      "description": "Must use new RedisStore({client}) instead of new RedisStore(client)",
      "impact": "high", "source_task": "T-001", "tags": ["redis", "breaking-change"]
    }
  ],
  "hot_files": [
    {
      "path": "src/routes/auth.ts", "modification_count": 5,
      "last_modified_by": "T-004", "last_modified_at": "2026-04-08T14:00:00Z",
      "risk_level": "high", "note": "Core auth route, full regression testing required on modification"
    }
  ]
}
```

### Field Descriptions

**tech_stack**: language, runtime, framework, database, cache, testing, deployment, ci_cd, other (string[])

**architecture_decisions (ADR)**: id (`ADR-NNN`), title, date, status (`proposed`/`accepted`/`deprecated`/`superseded`), context, decision, consequences, source_task, superseded_by

**lessons_learned**: id (`LL-NNN`), date, category (`dependency`/`testing`/`deployment`/`architecture`/`performance`/`security`/`other`), title, description, impact (`high`/`medium`/`low`), source_task, tags[]

**hot_files**: path, modification_count, last_modified_by, last_modified_at, risk_level (`high`≥5/`medium`≥3/`low`), note

### Auto-Update (Triggered on Task Accepted)

Task `accepted` → Read project-memory.json + T-NNN-memory.json → Extract updates:

1. **Architecture decisions**: Extract tech selection/architecture pattern-level decisions from designing.decisions. If same-topic ADR conclusion is identical → skip; if different → create new ADR + mark old ADR as superseded
2. **Lessons learned**: Extract reproducible issues from issues_encountered. Deduplicate (by tags/description similarity)
3. **Hot files**: Aggregate from files_modified, modification_count+1, recalculate risk_level
4. **Tech stack**: Scan decisions for "use/introduce/choose/adopt X" patterns, detect new tech → confirm then write

### Loading (Triggered on Agent Init)

Differentiated by role:

| Role | Loaded | Omitted |
|------|--------|---------|
| acceptor | tech_stack, ADR(all), hot_files | lessons_learned details |
| designer | tech_stack, ADR(all), LL(architecture category) | hot_files |
| implementer | tech_stack, ADR(accepted), LL(all), hot_files | deprecated ADRs |
| reviewer | tech_stack, ADR(accepted), hot_files, LL(all) | deprecated ADRs |
| tester | tech_stack(testing), LL(testing category), hot_files | ADRs |

**Integration**: agent-switch/agent-init → 📝 Load task memory → 🧠 Load project memory → Begin work

### Search (`/memory search <keyword>`)

Search project-memory.json: ADR (title/context/decision) ⭐⭐⭐ | LL (title/description/tags) ⭐⭐⭐ | tech_stack ⭐⭐ | hot_files (path/note) ⭐

**Combined search** ("search all memory"): Search project memory + all task memories simultaneously, merge, deduplicate, and sort by weight

---

## Context Budget Management

Total context budget allocation by role:

| Source | Acceptor | Designer | Implementer | Reviewer | Tester |
|--------|----------|----------|-------------|----------|--------|
| System prompt | 5k | 5k | 5k | 5k | 5k |
| Project context | 10k | 15k | 10k | 10k | 10k |
| Task context | 10k | 20k | 15k | 20k | 15k |
| Memory (Top-6) | 5k | 10k | 5k | 10k | 5k |
| Code context | 5k | 10k | 40k | 50k | 20k |
| Conversation | 145k | 120k | 105k | 85k | 125k |

**Priority when budget tight**: System prompt (never cut) → Task goals/status → Memory results → Code context → Project context → Conversation (oldest first)

**Smart Compression** near limit: Preserve decisions/ADRs/code changes → Compress discussion turns to summaries → Keep recent 10 turns verbatim → Older turns → one-line summaries

---

## Future Plans: Memory System 2.0

> **Not yet implemented.** Planned three-layer architecture: Layer 1 (MEMORY.md per-role, permanent), Layer 2 (daily diary YYYY-MM-DD.md, 30-90 day lifecycle), Layer 3 (PROJECT_MEMORY.md, shared). Will include SQLite FTS5 indexing, temporal decay scoring, and auto-promotion of high-signal diary entries to long-term memory.

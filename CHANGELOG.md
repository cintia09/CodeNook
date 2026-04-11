# Changelog

All notable changes to this project will be documented in this file.

## [3.3.6] - 2026-04-11

### 🔒 Security Hardening — Hook Enforcement

**Virtual Event Enforcement via preToolUse:**
- **agentSwitch**: validates role names on write to `active-agent`; blocks empty/invalid writes and file deletion (`rm`, `mv`)
- **memoryWrite**: namespace isolation — agents can only write their own memory files; task memory (`T-NNN-*`) is shared
- **taskBoard**: JSON syntax validation for full `task-board.json` writes

**Security Vulnerabilities Fixed:**
- **False positive prevention**: strip quoted strings (`'...'`, `"..."`) before pattern matching — prevents `--notes "npm publish"` from triggering block
- **Active-agent bypass**: block `rm`/`mv` on `active-agent` file; default to `acceptor` (most restrictive) when file missing but framework initialized
- **Chained command bypass**: per-segment analysis (`has_dangerous_segment`) splits on `&&`, `||`, `;` to prevent danger hidden behind whitelist matches
- **Multi-line quote stripping**: collapse newlines with `tr '\n' ' '` before `sed` to handle multi-line commit messages
- **Cross-directory attacks**: Strategy 4 extracts absolute paths from bash commands to detect operations targeting projects from outside directories

**Hook Configuration Cleanup:**
- Removed 6 unsupported custom events from `hooks-copilot.json` (Copilot CLI only supports 6 built-in events)
- Retained: `sessionStart`, `preToolUse`, `postToolUse`

### Added
- `tests/test-false-positive.sh` — 15 false-positive test cases
- `tests/test-virtual-events.sh` — 31 virtual event + security test cases
- 4-strategy project root detection (cwd walk, file path walk, cd target, absolute path extraction)

### Verified
- 51/51 total tests: framework 5/5 ✅, false-positive 15/15 ✅, virtual events 31/31 ✅
- Live-tested cross-directory, chained command, and active-agent bypass scenarios

## [3.3.5] - 2026-04-11

### Added
- **Comprehensive hard constraints for all 5 agent roles** via `preToolUse` hook enforcement
  - **Tester**: blocked from `git commit/push`, `rm/mv/cp` on non-test files, redirects outside test directories; allowed: `.agents/`, `tests/`, `*.test.*`, `*.spec.*`
  - **Implementer**: blocked from `npm publish`, `docker push`; blocked redirects to other agents' workspaces
  - **Acceptor/Designer**: read-only except `.agents/`; blocked destructive commands and redirects
  - **Reviewer**: read-only except `.agents/reviewer/`, `docs/`, `task-board`; blocked destructive commands

### Fixed
- **Bash redirect bypass vulnerability**: detected `>`, `>>`, `tee`, `sed -i`, `patch`, `dd` patterns in bash commands to prevent write operations that bypassed edit/create restrictions
- Redirect whitelist for `.agents/` writes per-role and test directories for tester role

### Verified
- 44/44 hook enforcement test scenarios passed across all 5 roles
- 8/8 live enforcement tests passed in real Copilot CLI session (tester role)

## [3.3.4] - 2026-04-11

### Fixed
- **agent-pre-tool-use.sh**: Fixed project root detection that failed when Copilot CLI session started from a non-project directory (e.g., `~`). Now walks up directory tree from both `cwd` and file path to find `.agents/` directory.

### Verified
- **Copilot CLI hooks confirmed working** (v1.0.24): `preToolUse` hook with `permissionDecision: "deny"` successfully blocks tool execution
- Both `~/.copilot/hooks/hooks.json` and `config.json` inline hooks are executed
- All 6 hook events documented by GitHub are supported: `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`

## [3.2.0] - 2026-04-10

### 🚀 Skills Mechanism Optimization (T-SKILL-OPT)

**R2: Per-Agent Skill Isolation:**
- All 5 `.agent.md` profiles now declare `skills:` allowlist in frontmatter
- Each agent has explicit "Skill 权限" section with positive and negative constraints
- Shared skills (7): orchestrator, fsm, task-board, messaging, memory, switch, docs
- Role-specific skills (11): config, init, acceptor, designer, implementer, reviewer, tester, events, hooks, hypothesis, teams

**R1: Token Distribution Documentation Fix:**
- `docs/llm-message-structure.md`: Corrected token pie chart from "18 Skills 全文 40%" to "Skills 摘要列表 1%"
- Added explanation of two-level loading mechanism (summary ~1% + on-demand full text)
- Updated ASCII packet structure to reflect summary-only skill injection
- Corrected "关键洞察" section to describe two-level loading

**R4: Dual Installation Methods in README:**
- "方式一: 一键安装" — `curl | bash` (script-driven)
- "方式二: 提示安装" — Tell AI assistant to install from repo (AI-guided)
- Added detailed manual install steps table (target directories per platform)
- Updated skill count from 15 to 18

## [3.1.5] - 2026-04-10

### 📝 Audit Round 10 — Convergence (2 doc fixes)

**Executable code: ZERO issues** — codebase converged ✅

**MEDIUM:**
- `agent-hooks/SKILL.md`: Fix Step→Agent table: `ci_monitoring` and `device_baseline` mapped to `tester` (was `implementer`)

**LOW:**
- `agent-hooks/SKILL.md`: Add 5 missing transitions to 3-Phase pseudocode (`design_review→test_scripting`, 4 hypothesis transitions)

## [3.1.4] - 2026-04-10

### 🔒 Security Audit Round 9 (16 issues fixed)

**HIGH:**
- `test-3phase-fsm.sh`: Fix `grep -q "LEGAL"` matching "ILLEGAL" — FSM test suite was non-functional
- `test-3phase-fsm.sh`: Add missing `design_review→test_scripting` in test FSM case statement
- `team-session.sh`: Escape agent names in tmux commands to prevent shell injection

**MEDIUM:**
- `install.sh`: Recreate TMP_DIR after cleanup — tarball install was falling through to git clone
- `agent-session-start.sh`: Use `PRAGMA busy_timeout=3000` instead of `.tables` for DB health check
- `auto-dispatch.sh`: Clear stale lock directories (>60s) to prevent permanent dispatch lockout
- `test-integration.sh`: Capture exit code before `set -e` masks staleness-check failures
- `install.sh`: Only backup hooks.json if `.bak` doesn't already exist (prevents overwriting user's original)
- `cron-scheduler.sh`: Document that `schedule` field is display-only, caller's crontab controls timing
- `agent-messaging/SKILL.md`: Clarify two `type` enum systems (auto-dispatch vs bidirectional)

**LOW:**
- `test-3phase-fsm.sh`: Fix label "26" → "27" legal transitions
- `test-integration.sh`: Remove dead `cp` immediately overwritten by `cat`
- `team-session.sh`: Validate `--agents/--task/--layout` have values (prevent `set -u` crash)
- `team-session.sh`: Portable `watch` fallback with `while sleep` loop for macOS
- `cron-scheduler.sh`: Fix file handle leak in Python `json.load(open(...))` → `with open()`
- `install.sh`: Add `trap 'rm -rf "$TMP_DIR"' EXIT` for cleanup on interrupt

## [3.1.3] - 2026-04-09

### 🚀 Strict Document Gate Mode

- `hooks/lib/fsm-validate.sh`: Document gate now supports `"strict"` mode — blocks transitions (`LEGAL=false`) when required docs are missing
- Configuration via `task-board.json` top-level field `"doc_gate_mode": "strict"` (default: `"warn"`)
- `skills/agent-docs/SKILL.md`: Updated with strict/warn mode documentation
- `skills/agent-fsm/SKILL.md`: Added document gate as guard #5 in FSM validation rules
- `tests/test-integration.sh`: 2 new tests (strict blocks, warn allows) — 25 total

## [3.1.2] - 2026-04-09

### 🔒 Security Audit Round 7 (10 issues fixed)

**HIGH:**
- `agent-before-memory-write.sh`: Block path traversal (`..`) in memory file paths

**MEDIUM:**
- `agent-before-compaction.sh`: Validate agent name against `[a-z_-]+` allowlist
- `agent-fsm/SKILL.md`: Document `design_review→test_scripting` transition (was in code but not docs)
- `test-integration.sh`: Fix hypothesis test field name `.path` (was `.file_path`, test was vacuous)
- `cron-scheduler.sh`: Use `project_dir` for task-board path in generate-report
- `team-session.sh`: Escape `PROJECT_DIR` in dashboard pane tmux command

**LOW:**
- `test-3phase-fsm.sh`: Add `design_review:test_scripting` to legal transitions test array
- `agent-pre-tool-use.sh`: Add tester bash restrictions (block git push, npm publish, docker run)
- `install.sh`: Narrow chmod +x to `agent-*.sh` + `security-scan.sh` only

## [3.1.1] - 2026-04-09

### 🔒 Security Audit Round 6 (16 issues fixed)

**HIGH:**
- `install.sh`: Fixed symlink attack — tarball now extracts directly to mktemp dir with `--strip-components=1`
- `webhook-handler.sh`: Added `|| true` to sqlite3 call; log previous agent on switch
- `verify-init.sh`: Replaced all python3 code injection vectors with jq; fixed shebang + `set -euo pipefail`
- `agent-pre-tool-use.sh`: Reviewer now allowed to write `.agents/docs/` (fixes doc gate/boundary conflict)

**MEDIUM:**
- `cron-scheduler.sh`: Pass shell vars via `os.environ` instead of interpolating into Python strings
- `fsm-validate.sh`: Convergence gate uses `$NEW_STATUS` (not `$NEW_STATUS_SQL`); escape PT_* in JSON
- `auto-dispatch.sh`: Moved duplicate check inside lock to prevent TOCTOU race condition
- `team-session.sh`: Escape single quotes in TASK_FILTER and PROJECT_DIR for tmux
- `test-integration.sh`: Fixed hypothesis test using wrong field names (was snake_case, now camelCase)
- `install.sh`: Removed `git config --global http.postBuffer` side effect

**LOW:**
- `agent-pre-tool-use.sh`: Quote `$CWD` in parameter expansion to prevent glob interpretation
- `team-dashboard.sh`: Fixed progress bar off-by-one at 0%
- `webhook-handler.sh`: Log previous agent name on webhook-triggered switch
- `test-3phase-fsm.sh`: Removed redundant rm -rf (EXIT trap handles cleanup)
- `fsm-validate.sh`: SQL-escape PT_* values in convergence gate JSON

## [3.1.0] - 2026-04-09

### 🚀 Agent Teams — Bidirectional Messaging, Parallel Execution, Competitive Hypothesis

**New Features:**
- **Bidirectional Messaging**: Added `thread_id`, `reply_to` fields to message schema; `broadcast` message type for team-wide announcements
- **tmux Team Session**: `scripts/team-session.sh` launches multi-agent split-pane session with auto-refresh dashboard
- **Team Dashboard**: `scripts/team-dashboard.sh` shows real-time agent status, inbox counts, pipeline progress bar, recent events
- **Competitive Hypothesis**: New `agent-hypothesis` skill (18th skill) — Fork/Evaluate/Promote pattern for parallel approach exploration
- **`hypothesizing` FSM state**: New state in both Simple and 3-Phase workflows; `designing→hypothesizing` and `implementing→hypothesizing` transitions
- **Inbox on Switch**: After-switch hook now shows unread message count with urgent priority highlighting

**Enhancements:**
- `agent-messaging/SKILL.md`: Added thread support, broadcast type, updated routing rules
- `agent-teams/SKILL.md`: Added tmux session architecture, competitive hypothesis pattern, workspace storage
- `agent-fsm/SKILL.md`: Added `hypothesizing` to universal transitions
- `auto-dispatch.sh`: `hypothesizing` status skips auto-dispatch (coordinator manages)
- README: Added "Agent Teams" section with architecture diagram, 3 features, usage scenarios
- Integration tests expanded 21→23 (hypothesis transition + team dashboard)

## [3.0.23] - 2026-04-09

### 🔒 Security Audit Round 5 (16 issues fixed)

**HIGH:**
- `agent-post-tool-use.sh`: Fixed ACTIVE_AGENT double-escaping — raw value now stored, escaped only at SQL use sites (H1)
- `agent-post-tool-use.sh`: All sqlite3 calls now have `2>/dev/null || true` to prevent hook crash on DB errors (H2)
- `auto-dispatch.sh`: `created` status now routes to acceptor in 3-phase mode (was always designer) (H3)

**MEDIUM:**
- `fsm-validate.sh`: Added `design_review→test_scripting` transition (M1)
- `agent-fsm/SKILL.md`: Fixed ci_monitoring/device_baseline agent assignment (implementer→tester) (M2)
- `fsm-validate.sh`: Document gate now covers 3-phase states + acceptance-criteria.md (M3)
- `agent-post-tool-use.sh`: Reordered modules — FSM validation runs BEFORE auto-dispatch (M4)
- `memory-capture.sh`: Skips FSM-violated tasks to avoid capturing illegal transitions (M5)
- `fsm-validate.sh`: Goal guard uses `$NEW_STATUS` instead of `$NEW_STATUS_SQL` for comparison (M6)
- `install.sh`: Uses `mktemp -d` instead of predictable `/tmp/multi-agent-framework` path (M7)
- `agent-pre-tool-use.sh`: grep pattern uses `(\s|$)` to catch commands at end of line (M8)

**LOW:**
- `test-3phase-fsm.sh`: Added trap for temp dir cleanup (L1)
- `install.sh`: Split `local` declarations from assignments to avoid masking exit codes (L2)
- `verify-install.sh`: Replaced python3 path-injection-prone JSON check with jq (L4)
- `cron-scheduler.sh`: Resolved subprocess paths relative to script directory (L5)

## [3.0.22] - 2026-04-09

### 🔒 Security Audit Round 4 (22 issues fixed)

**CRITICAL:**
- `install.sh`: Now copies `hooks/lib/` directory (auto-dispatch, fsm-validate, memory-capture modules were missing after install!)

**HIGH — SQL/Code Injection:**
- `session-start.sh`: TIMESTAMP numeric validation (missed in Round 1)
- `memory-search.sh`: escape QUERY, ROLE, LAYER params; validate LIMIT is numeric
- `security-scan.sh`: sanitize newlines in JSON output (was producing invalid JSON)

**MEDIUM — Correctness & Safety:**
- `memory-capture.sh`: use jq for memory file JSON (fixes title with double quotes)
- `post-tool-use.sh`: escape double quotes/backslashes in TOOL_ARGS detail JSON; fix TOCTOU race (snapshot from cache, not disk)
- `install.sh`: fix operator precedence in integrity check; consistent skill count (17)
- `fsm-validate.sh`: compare raw status (not sql-escaped) for blocked_from
- `staleness-check.sh`: fix Perl code injection via environment variable
- `auto-dispatch.sh`: use @tsv (tab) instead of pipe delimiter; fail-safe lock skip
- `verify-install.sh`: add agent-docs to skill check list; threshold 16→17
- `agent-after-switch.sh`: jq for JSON output; null-safety for assigned_to
- `agent-before-task-create.sh`: jq for JSON output

**LOW — Hardening:**
- `config.sh`: use escaped values in sed append; escape regex in tool removal
- Test schema aligned with production (created_at column)
- Test #14 validates exit code + output (no false pass on crash)
- Remove redundant staleness-check from PostToolUse hooks.json
- `memory-index.sh`: track + report actual indexed count
- `webhook-handler.sh`: validate CWD before writing files

## [3.0.21] - 2026-04-09

### 🔒 Security Audit Round 3 (12 issues fixed)

**HIGH — SQL Injection:**
- `webhook-handler.sh`: escape PAYLOAD before SQL insertion
- `memory-index.sh`: escape file paths and checksum in all SQL queries

**MEDIUM — Security & Correctness:**
- `auto-dispatch.sh`: escape ACTIVE_AGENT in SQL JSON detail
- `memory-capture.sh` + `fsm-validate.sh`: fix `||`/`&&` operator precedence bug (guard clause now uses explicit `if/fi`)
- `agent-after-switch.sh`: replace jq `first` (1.6+) with `.[0]` for older jq compat; add null-safety for `.assigned_to`
- `agent-post-tool-use.sh`: validate task-board.json with `jq empty` before processing
- `auto-dispatch.sh`: fail-safe lock timeout (skip instead of proceeding unprotected)
- `config.sh`: escape special chars in sed replacement patterns

**LOW — Hardening:**
- `agent-pre-tool-use.sh`: escape agent name in JSON error output
- `agent-after-switch.sh`: replace unsafe `ls *.md` with `find -name "*.md"`

## [3.0.20] - 2026-04-09

### ⚡ Performance Optimization

**`fsm-validate.sh`**: Reduced jq calls from O(10×N) to O(2) total per hook invocation:
- Pre-extract ALL task fields (id, status, workflow_mode, feedback_loops, blocked_from, goals, parallel_tracks) in ONE jq call using `@tsv`
- Pre-load snapshot statuses with single jq call + awk lookup
- Eliminated 4 consecutive parallel_tracks queries (→ pre-extracted)
- Deduplicated `blocked_from` extraction across simple/3phase validators

**`memory-capture.sh`**: Same pattern — single jq call for all task data.

**`agent-staleness-check.sh`**:
- Cache date tool detection at startup (try once, reuse) instead of 3-tool fallback per call
- Consolidate 3→1 jq calls per state.json file

### 🧪 Integration Tests Expanded (12 → 21)

New tests: pre-tool-use agent boundaries (acceptor/implementer/reviewer), before-memory-write (empty/wrong-path/valid), on-goal-verified event logging, session-start event, staleness-check execution.

### 📖 README

- Added "已知限制 & 常见问题" (Known Limitations & Troubleshooting) section

## [3.0.19] - 2026-04-09

### 🔧 Hook Modularization

Split the 364-line `agent-post-tool-use.sh` monolith into a clean 79-line main hook + 3 focused modules:

- `hooks/lib/auto-dispatch.sh` (75 lines) — message routing on status change
- `hooks/lib/fsm-validate.sh` (171 lines) — FSM transitions, goal guard, doc gate, feedback limit
- `hooks/lib/memory-capture.sh` (49 lines) — status transition detection + memory init

### 🧪 Integration Tests

- New `tests/test-integration.sh` with 12 actual hook execution tests
- Covers: tool logging, auto-dispatch, FSM violation, doc gate, memory capture, after-switch, compaction, security scan, before-task-create, events DB
- Added to `tests/run-all.sh` — full suite now 5/5

### 📄 Other

- `agent-init` skill now auto-creates `.agents/docs/` directory
- README: added document pipeline section with flow diagram

## [3.0.18] - 2026-04-09

### 📄 New Feature: Document Pipeline (`agent-docs` skill)

**Core concept**: Each SDLC phase must produce standardized documents that serve as inputs to the next phase.

**Document flow matrix**:
| Phase | Agent | Input | Output |
|-------|-------|-------|--------|
| Requirements | Acceptor | user request | `requirements.md` + `acceptance-criteria.md` |
| Design | Designer | requirements.md | `design.md` |
| Implementation | Implementer | requirements + design | `implementation.md` |
| Review | Reviewer | requirements + design + implementation | `review-report.md` |
| Testing | Tester | requirements + design + implementation | `test-report.md` |
| Acceptance | Acceptor | acceptance-criteria + all docs | Accept/Reject |

**What's included**:
- New `agent-docs` skill with 6 document templates (requirements, acceptance-criteria, design, implementation, review-report, test-report)
- Storage convention: `.agents/docs/T-XXX/` per task
- FSM document gate: warns when transitioning without required output document
- After-switch hook: lists available input documents for the current task
- All 5 agent profiles updated with explicit document input/output requirements
- 3-Phase mode document mapping included

## [3.0.17] - 2026-04-09

### 🐛 Deep Audit Round 2 (20 issues fixed)

**Security & Robustness:**
- **CWD extraction** in `agent-before-task-create.sh` — duplicate check now works from any directory
- **Lock release safety** — jq/mv failures no longer leave stale tmp files
- **grep pattern portability** in `security-scan.sh` — single-quote matching works across all grep implementations
- **CWD validation** in `security-scan.sh` — graceful exit if directory invalid
- **Download integrity** in `install.sh` — verify key files exist after tarball extraction
- **Copilot rules write check** — warn if append to copilot-instructions.md fails

**Cross-Platform Compatibility:**
- **Portable sed** in `config.sh` — `_sed_i()` helper detects macOS vs Linux (fixes `sed -i ''` failure on Linux/CI)
- **Portable date parsing** in `agent-staleness-check.sh` — replaced python3 fallback with perl `Time::Piece` (faster, no timeout risk)

**FSM Logic & Safety:**
- **Simple mode feedback loop protection** — `reviewing→implementing`, `testing→fixing`, `accept_fail→designing` now capped at 10 loops
- **Convergence gate event logging** — gate failures now logged to events.db (audit trail)
- **Unblock warnings** — tasks unblocked without `blocked_from` record get visible warning

**Memory & State:**
- **Memory directory creation check** — explicit error if `mkdir -p` fails
- **Compaction hook guard** — skip diary flush if no active agent found

**Documentation:**
- **README skill count** — badge updated 15→16, added `agent-config` to skills table
- **Section anchor** — `#15-个-skills` → `#16-个-skills`

## [3.0.16] - 2026-04-09

### 🐛 Critical Bug Fixes (Security & Reliability Audit)
- **TIMESTAMP SQL injection** — validate timestamp is numeric before SQL insertion
- **Pipe subshell variable loss** — convert `| while` to `while ... done < <(...)` in agent-post-tool-use.sh and agent-staleness-check.sh; staleness detection was completely broken
- **macOS file locking** — replace Linux-only `flock` with portable `mkdir`-based atomic lock
- **JSON null validation** — guard TASK_ID/NEW_STATUS against null/empty before FSM processing
- **TOOL_ARGS truncation order** — truncate before SQL escaping (not after) to prevent broken escape sequences
- **CWD initialization** — add INPUT/CWD extraction to 5 hooks missing it (after-memory-write, after-task-status, before-compaction, on-goal-verified, after-switch)

## [3.0.15] - 2026-04-09

### ✨ New Skill: agent-config
- **CLI model configuration** — `config.sh model set <agent> <model>` to configure agent models
- **CLI tools management** — `config.sh tools set/add/rm/reset` to control per-agent tool access
- **Dynamic agent discovery** — auto-scans all `*.agent.md` files, no hardcoded list
- **Dynamic model discovery** — `config.sh models` queries platform CLIs for available models
- **Dual-platform sync** — all changes applied to `~/.claude/agents/` and `~/.copilot/agents/` simultaneously
- **Backward compatible** — old `config.sh set/reset` commands still work

### 🔔 Model Switch Hints
- **agent-after-switch hook** — reads agent's `model` field on switch, suggests `/model <id>` command
- If `model` configured → "📌 Use /model xxx to switch"
- If only `model_hint` → "💡 hint information"
- If neither → silent (no noise)

### 🔧 Fixes
- **verify-install.sh** — updated skill count 15→16 (added agent-config)
- **SKILL.md interactive workflow** — AI now mandated to run discovery commands first, not assume agent/model lists

## [3.0.14] - 2026-04-09

### 🤝 Copilot Parity
- **Full Copilot CLI support** — installer now detects `~/.copilot` and auto-installs agents + skills + hooks + rules (same as Claude Code)
- **Agent profiles for Copilot** — 5 `.agent.md` files installed to `~/.copilot/agents/` (Copilot CLI natively supports custom agents via `/agent`)
- **Dual-platform check_install** — `--check` reports status for both Claude Code and Copilot CLI
- **Dual-platform uninstall** — `--uninstall` cleans both `~/.claude` and `~/.copilot` agent files

### 📝 Documentation
- **Updated platform compatibility table** — README now shows full parity between Claude Code and Copilot CLI
- **English usage instructions** — installer Done message now in English

## [3.0.13] - 2026-04-09

### ✨ Features
- **Per-agent model config** — added `model` and `model_hint` fields to all 5 agent profiles
- **Project-type-aware init** — agent-init Step 1c classifies projects (ios/frontend/backend/systems/ai-ml/devops) and adapts skill generation per type
- **Model resolution in agent-switch** — priority: task override → agent model → project config → system default

## [3.0.12] - 2026-04-09

### ⚡ Performance
- **Task-board cache** — cached task-board.json content in variable (15→1 disk reads per hook invocation)

### 🛡️ Resilience
- **events.db auto-repair** — session-start validates schema with `.tables` check, auto-recreates corrupted DB

### 🔧 CI/CD
- **GitHub Actions CI** — added `.github/workflows/test.yml`, runs all tests on push/PR to main

## [3.0.11] - 2026-04-09

### 📝 Documentation
- **Add 3-Phase sections** to implementer, reviewer, tester SKILL.md — each role now documents its 3-Phase responsibilities, steps, and differences from Simple mode
- **Trim monitoring diagrams** — replaced 48-line ASCII flowcharts with concise 5-step numbered lists (implementer −22 lines, tester −21 lines)

## [3.0.10] - 2026-04-09

### 🐛 Critical Fix
- **Fix undefined variables in auto-memory-capture** — `OLD_STATUS_SQL`/`NEW_STATUS_SQL`/`TASK_ID_SQL` were from a separate pipe subshell; memory events were never logged

### 🔒 Security
- **Bash command boundary enforcement** — acceptor, designer, reviewer now blocked from destructive bash commands (`rm`, `mv`, `git push`, `npm publish`, `docker run`, etc.)

### 🔧 Improvements
- **Improved uninstall()** — now removes security-scan.sh, rules/ files, restores hooks.json from `.bak`, cleans up Copilot installation

## [3.0.9] - 2026-04-09

### 🔧 Improvements
- **Standardize hook paths** — all 7 hooks with bare `.agents/` paths now use `AGENTS_DIR="${CWD:-.}/.agents"` variable
- **Clarify flock portability** — Linux-only with graceful no-op on macOS
- **CONTRIBUTING.md** — added dual-platform hook format comparison table (PascalCase vs camelCase, command vs bash, timeout ms vs sec)

### 🧪 Tests
- **test-hooks.sh expanded** — JSON validity checks for both hooks.json files, event count parity, rules/ validation, shebang + pipefail enforcement

## [3.0.8] - 2026-04-09

### 🐛 Critical Fix
- **Fix variable use-before-define** in `agent-post-tool-use.sh` — `OLD_STATUS_SQL`/`NEW_STATUS_SQL` were referenced before assignment, causing FSM validation to silently skip; also fixed self-referencing `sql_escape()` calls

### 🔧 Improvements
- **Complete Copilot hooks.json**: Added 6 missing event types (agentSwitch, taskCreate, taskStatusChange, memoryWrite, compaction, goalVerified) — Copilot users now get full hook coverage
- **verify-install.sh hardened**: Shebang → `#!/usr/bin/env bash`, error handling → `set -euo pipefail`

## [3.0.7] - 2026-04-09

### 🐛 Bug Fixes
- **README.md**: Fixed unclosed code fence after task lifecycle diagram — headings and text were rendered inside code block
- **install.sh hook count**: Fixed glob pattern (`agent-*.sh` → `*.sh`) to include `security-scan.sh` (12/13 → 13/13)
- **install.sh threshold**: Raised completeness check from 12 to 13 hooks

### 🔧 Improvements
- **hooks.json backup+replace**: Install now backs up existing hooks.json before overwriting (creates `.bak`) instead of skipping — applies to both Claude and Copilot platforms

## [3.0.6] - 2026-04-08

### 🔒 Security
- **CRITICAL: Fix SQL injection** in 11 sqlite3 calls across 6 hooks — all variables now escaped via `sql_escape()` helper
- **Expanded secret scanning**: Add detection for Stripe keys, Slack tokens, database connection strings, JWT/Bearer tokens, webhook URLs

### 🔧 Improvements
- **python3→jq migration**: All 7 hooks now use jq for JSON parsing (consistent, lighter, portable)
- **Shebang standardization**: All 13 hooks now use `#!/usr/bin/env bash` (was mixed `#!/bin/bash`)
- **SQLite error handling**: All hooks now log warnings on insert failure instead of silent suppression
- **.gitignore hardened**: Add agent runtime files (events.db, state.json, inbox.json, snapshots, logs, backups)

## [3.0.5] - 2026-04-08

### ⚡ Performance
- **SKILL.md context reduction**: agent-init 680→173 (−75%), agent-switch 588→141 (−76%)
- Total across 4 files: 3654→1116 lines (−69%, ~10K tokens/session)

## [3.0.4] - 2026-04-08

### 📦 New Features
- **FSM unblock validation**: `blocked→X` now restricted to `blocked→blocked_from` state only (prevents state-skipping)
- **Goal guards**: Acceptance (`→accepted`) blocked unless ALL goals have `status=verified`
- **11 new behavioral tests**: Unblock validation (5 tests) + goal guard (6 tests) — total 31 FSM tests

### ⚡ Performance
- **SKILL.md context reduction**: agent-orchestrator 1394→500 lines (−64%), agent-memory 992→302 lines (−70%)

### 🔧 Improvements
- **Consolidated hooks**: Merged memory-index trigger from agent-after-task-status.sh into agent-post-tool-use.sh (single source of truth)
- **SQLite error handling**: agent-after-task-status.sh now logs warnings on failure

## [3.0.3] - 2026-04-08

### ⚡ Performance
- **jq loop optimization**: Auto-dispatch now uses pipe-delimited parsing (3 jq calls → 1 per task)
- **SQLite transactions**: `memory-index.sh` wraps all inserts in a single transaction (atomicity + ~10x speed)

### 🐛 Bug Fixes
- **File locking**: Add `flock`-based locking on inbox.json writes to prevent race conditions
- **Cross-platform dates**: Add python3 fallback for ISO date parsing (macOS + Linux + containers)
- **SQLite error logging**: Replace silent `2>/dev/null || true` with proper warning on failure
- **Shell safety**: Standardize `set -euo pipefail` across all 6 hook scripts

### 📦 New Features
- **Orphan task detection**: Staleness check now flags blocked tasks with no activity >48h (🔴 warning)

## [3.0.2] - 2026-04-08

### 🐛 Bug Fixes
- **CRITICAL**: Fix missing `accepting→accept_fail` FSM transition in Simple mode validation — previously blocked all acceptance failure flows
- **macOS compatibility**: Replace `grep -P` (GNU-only) with `sed` in agent-post-tool-use.sh — fixes silent failure on macOS
- **Shell injection**: Fix unsanitized `$TASK_ID` in agent-before-task-create.sh — now passed via env var
- **Broken paths**: Fix `scripts/memory-index.sh` references in hooks — now searches `.agents/scripts/` and `scripts/` with fallback
- **3-Phase auto-dispatch**: Add all 15 3-Phase state→agent mappings to post-tool-use dispatch — previously only Simple mode states were dispatched

### 📦 New Features
- **Modular rules** (`rules/`): Leverage Claude Code's native `.claude/rules/` system with path-scoped rules
  - `agent-workflow.md` — Role + FSM rules (scoped to `.agents/**`, `hooks/**`, `skills/**`)
  - `security.md` — Secret scanning rules (scoped to code files)
  - `commit-standards.md` — Conventional commit format
- **Platform compatibility table**: Document Claude Code vs GitHub Copilot support matrix

### 📝 Documentation
- Fix README lifecycle diagram: add missing `accepting → accept_fail → designing` path
- Fix duplicate "Claude Code、Claude Code" → "Claude Code、GitHub Copilot"
- Fix "15+ Hook" → "13 Hook" in skills table and roadmap
- Fix staleness-check event type: SessionStart → PostToolUse (matches hooks.json)
- Update docs/agent-rules.md with 3-Phase workflow rules
- Update install.sh to install modular rules to `~/.claude/rules/`
- Update AGENTS.md: fix chmod for security-scan.sh, fix hook count verification
- Add rules/ directory structure to README file tree

### 🧪 Tests
- Expand test-hooks.sh from 5 to 13 hooks (full v2.0 coverage)

## [3.0.0] - 2026-04-12

### 🚀 Major Release — 3-Phase Engineering Closed Loop

#### Phase 13: 3-Phase Engineering Closed Loop
- **Dual-mode FSM**: Tasks now support `workflow_mode: "simple"` (default, backward compatible) or `"3phase"` (new)
- **18 new FSM states** across 3 phases for the 3-Phase workflow:
  - Phase 1 — Design: requirements → architecture → tdd_design → dfmea → design_review
  - Phase 2 — Implementation: implementing + test_scripting (parallel) → code_reviewing → ci_monitoring/ci_fixing → device_baseline
  - Phase 3 — Testing & Verification: deploying → regression_testing → feature_testing → log_analysis → documentation
- **Orchestrator daemon**: Background shell script that autonomously drives 3-Phase tasks end-to-end
- **Parallel tracks**: Phase 2 runs 3 concurrent tracks (implementer, tester, reviewer) with convergence gate
- **Feedback loops**: Phase 3 → Phase 2 (test failure), Phase 2 → Phase 1 (design gap), with MAX_FEEDBACK_LOOPS=10 safety limit
- **Pluggable external systems**: CI (GitHub Actions/Jenkins/GitLab CI), Code Review (GitHub PR/Gerrit/GitLab MR), Device/Test environment — all configurable via `{PLACEHOLDER}` tokens
- **16 prompt templates**: Step-specific prompts for autonomous agent invocation, generated during project init
- **Convergence gate**: All parallel tracks must complete before device_baseline
- **Feedback safety**: Auto-block tasks that exceed 10 feedback loops
- **New skill**: `agent-orchestrator` (3-Phase daemon management + prompt templates)
- Extended `agent-fsm` with 3-Phase state definitions, transitions, and guard rules
- Extended `agent-hooks` with 3-Phase dispatch logic, convergence validation, feedback counting
- Extended `agent-init` with workflow mode selection and 3-Phase initialization (orchestrator + prompts)
- Extended `agent-teams` with Phase 2 parallel track documentation
- Extended `agent-post-tool-use.sh` with dual-mode FSM validation (simple + 3-phase)
- Extended `task-board.json` schema with `workflow_mode`, `phase`, `step`, `parallel_tracks`, `feedback_loops`, `feedback_history` fields

### 📊 Stats
- Skills: 14 → **15** (+agent-orchestrator)
- FSM States: 10 (simple) + **18** (3-phase)
- Prompt Templates: **16** (generated per project)
- Workflow Modes: **2** (simple + 3-phase)
- Feedback Safety Limit: 10 loops per task

## [2.0.0] - 2026-04-07

### 🚀 Major Release — 5 New Phases

#### Phase 8: Memory 2.0
- Three-layer memory architecture (MEMORY.md long-term + diary/YYYY-MM-DD.md + PROJECT_MEMORY.md shared)
- SQLite FTS5 full-text indexing with unicode61 tokenizer (`scripts/memory-index.sh`)
- Hybrid search CLI with role/layer/limit filters (`scripts/memory-search.sh`)
- Memory lifecycle: 30-day temporal decay, 6-signal auto-promotion scoring
- Compaction-safe memory flush

#### Phase 9: Hook System 2.0
- Expanded from 5 hooks to **13 scripts** across **9 event types**
- New lifecycle hooks: AgentSwitch, TaskCreate, TaskStatusChange, MemoryWrite, Compaction, GoalVerified
- Block/Approval semantics — hooks can return `{"block": true}` to prevent operations
- Priority chains — multiple hooks execute in order, block stops chain
- Per-role tool profiles in `.agents/tool-profiles.json`
- New skill: `agent-hooks` (hook lifecycle management)

#### Phase 10: Scheduling & Automation
- Cron scheduler (`scripts/cron-scheduler.sh`) with `jobs.json` configuration
- Webhook handler (`scripts/webhook-handler.sh`) for GitHub push/PR/CI events
- FSM auto-advance — task completion auto-triggers next agent switch

#### Phase 11: Context Engine
- Token budget allocation per agent role
- Role-aware bootstrap injection (global skill + project skill + task + memory Top-6)
- Intelligent compression preserving key decisions

#### Phase 12: Agent Teams
- Subagent spawn protocol for parallel task execution
- Multi-implementer parallel pattern
- Parallel review coordination
- New skill: `agent-teams` (team orchestration)

### 📊 Stats
- Skills: 12 → **14** (+agent-hooks, +agent-teams)
- Hooks: 5 scripts / 3 events → **13 scripts / 9 events**
- Scripts: 2 → **6** (+memory-index, memory-search, cron-scheduler, webhook-handler)

## [1.0.0] - 2026-04-06

### 🎉 Initial Release

#### Phase 1: Core Framework
- 5 Agent roles: Acceptor, Designer, Implementer, Reviewer, Tester
- FSM state machine with 10 states and guard rules
- Task board with optimistic locking
- Goals-based task tracking (pending → done → verified)
- Agent messaging via inbox.json

#### Phase 2: Enforcement & Auditing
- Shell hooks for agent boundary enforcement
- Pre-tool-use boundary checking
- Post-tool-use audit logging
- SQLite events.db for activity tracking
- Security scan (pre-commit secret detection)

#### Phase 3: Automation
- Auto-dispatch: task state changes trigger downstream agent notification
- Staleness detection: warn on tasks idle > 24 hours
- Batch processing mode: agents process all pending tasks in a loop
- Monitor mode: Tester ↔ Implementer auto fix-verify cycle
- Structured issue tracking (JSON + optimistic locking)

#### Phase 4: Memory & Visualization
- Auto memory capture on FSM stage transitions
- Smart memory loading (role-based field filtering)
- ASCII pipeline visualization in agent status panel
- Project-level living documents (6 docs in docs/)
- Event summary in status panel (24h activity per agent)

#### Phase 5: Best Practices Integration
- Implementer: TDD discipline (RED/GREEN/REFACTOR + git checkpoints + 80% coverage gate)
- Implementer: Build fix workflow (one error at a time)
- Implementer: Pre-review verification (typecheck → build → lint → test → security)
- Reviewer: Severity levels (CRITICAL/HIGH/MEDIUM/LOW) with approval rules
- Reviewer: OWASP Top 10 security checklist
- Reviewer: Code quality thresholds (function >50 lines, file >800 lines, nesting >4)
- Reviewer: Confidence-based filtering (≥80% confidence)
- Reviewer: Design + code review (can route back to designer)
- Tester: Coverage analysis workflow
- Tester: Flaky test detection and quarantine
- Tester: E2E testing with Playwright Page Object Model
- Designer: Architecture Decision Records (ADR)
- Designer: Goal coverage self-check
- Acceptor: User story format for goals

## v3.2.1

### R3: Architecture Docs Update
- Rewrote `docs/skills-mechanism.md` with 5 updated Mermaid diagrams
- New: Two-level loading sequence diagram (summary ~1% + on-demand full text)
- New: Skill discovery paths comparison (Claude Code vs Copilot CLI)
- New: Per-Agent skill isolation flowchart with shared/role-specific allocation
- Updated: Three-layer behavior control (added skill constraints)
- Updated: Request lifecycle (reflects two-level loading + doc gate)

### R5: Conditional Activation (Partial)
- Added `paths:` frontmatter to `agent-hooks` skill (`hooks/**`, `**/*.sh`, config files)
- Documented `paths:` feature in skills-mechanism.md platform comparison table
- Role skills (tester, implementer) excluded to avoid breaking agent workflow

## v3.2.2

### Documentation Cleanup
- Fix stale references: skill count 14/15/17→18 across README, USAGE_GUIDE, badges
- Update claude-code-flow.md: two-level Skill loading + per-agent isolation diagram
- Update agent-rules.md: remove stale state.json, add skills: isolation mention
- Simplify README: condense issue tracking + memory sections, collapsible narrative
- Fix doc gate limitation entry: strict mode now exists (was listed as planned)
- README: 734→682 lines (−7%)

## v3.2.3

### agent-init Rework
- Step 1b: Scan both CLAUDE.md and .github/copilot-instructions.md
- Step 1e: Scan all 18 global skills (was only 7), read agent profiles with skills: isolation
- Step 1f: NEW — detect platform (Claude Code / Copilot CLI / both)
- Step 3: Remove stale state.json references
- Step 6: Fix .gitignore (remove state.json)
- Step 7: NEW — generate/update CLAUDE.md + copilot-instructions.md with framework refs
- Step 7c: NEW — auto-append .agents runtime paths to project .gitignore
- Step 8: Updated summary with platform + global skill count

## v3.2.4

### Skills Loading Animation
- Interactive HTML animation (8 steps, keyboard/auto-play)
- GIF (378KB) + MP4 (152KB) versions for sharing
- Visualizes two-level loading, per-agent isolation, token efficiency

### Audit Round 11
- 1 doc-only issue fixed (stale version in USAGE_GUIDE)
- Executable code: ZERO issues for 3rd consecutive round

## v3.3.0

### Worktree-Based Parallel Tasks
- NEW `agent-worktree` skill: create/list/merge/status commands
- Each task gets isolated worktree + branch (task/T-XXX)
- Shared task-board.json + events.db via symlink
- Isolated runtime (inbox, memory, docs) per worktree
- Auto-copy memory/docs back to main on merge

### Framework Updates
- Skill count: 18 → 19 (agent-worktree added as shared skill)
- Shared skills: 7 → 8 (all agents get worktree access)
- Updated all 5 agent profiles + skills-mechanism diagram
- Design doc: `.agents/docs/T-WORKTREE/design.md`

## v3.3.1

### Worktree P2-P5 Implementation
- P2: `team-session.sh --worktree --tasks T-042,T-043` (one tmux window per task)
- P3: auto-dispatch cross-worktree message routing
- P4: task-board.json `worktree` field (path/branch/created_at)
- P5: USAGE_GUIDE §3.4 + 5 new integration tests (30 total)

## v3.3.2

### Forced Natural Language Agent Switch
- agent-switch SKILL.md: expanded description with 7 trigger patterns (CN+EN)
- Added mandatory trigger rules section with name mapping table
- agent-rules.md: new "强制角色切换" top-priority section
- agent-init Step 7a: CLAUDE.md template now includes switch trigger rules
- Supports: "切换到验收者", "switch to tester", "/agent acceptor", "我是实现者", etc.

## v3.3.3

### Role Permission Enforcement
- agent-rules.md: new "角色权限强制执行" section with permission matrix
- Self-check before every file operation: read active-agent → check matrix → block violations
- Violation response template: shows role, blocked action, and switch suggestion
- agent-init Step 7a: CLAUDE.md template includes enforcement rules
- Works in both Claude Code (hook-enforced) and Copilot CLI (self-check enforced)

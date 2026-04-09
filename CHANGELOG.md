# Changelog

All notable changes to this project will be documented in this file.

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

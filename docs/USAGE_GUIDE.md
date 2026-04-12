# 🤖 Multi-Agent Framework Usage Guide

> An AI-powered software engineering pipeline — 5 AI Agents collaborating through the full SDLC

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [Core Concepts](#2-core-concepts)
3. [Workflow Details](#3-workflow-details)
4. [Advanced Features](#4-advanced-features)
5. [Command Reference](#5-command-reference)
6. [Best Practices](#6-best-practices)
7. [Configuration Reference](#7-configuration-reference)
8. [3-Phase Engineering Closed Loop Guide](#8-3-phase-engineering-closed-loop-guide)

---

## 1. Quick Start

### 1.1 Installation

**One-line install (recommended):**
```bash
curl -sL https://raw.githubusercontent.com/cintia09/multi-agent-framework/main/install.sh | bash
```

**Manual install:**
```bash
git clone https://github.com/cintia09/multi-agent-framework.git /tmp/maf
cp -r /tmp/maf/skills/agent-* ~/.claude/skills/
cp /tmp/maf/agents/*.agent.md ~/.claude/agents/
cp /tmp/maf/hooks/*.sh ~/.claude/hooks/
cp /tmp/maf/hooks/hooks.json ~/.claude/hooks/
chmod +x ~/.claude/hooks/*.sh
```

**Verify installation:**
```bash
bash install.sh --check
# Output:
#   Skills: 19/18
#   Agents: 5/5
#   Hooks:  13
#   hooks.json: ✅
```

### 1.2 Initialize a Project

In any project root directory, tell Claude Code:

```
Initialize Agent system
```

The Agent will automatically:
1. Detect project tech stack (language, framework, test tools, CI/CD)
2. Create the `.agents/` runtime directory
3. Generate 6 project-level Skills (customized based on detected tech stack)
4. Initialize empty task board, event database, and Agent state files
5. Create `docs/` living document templates

**Directory structure after initialization:**
```
.agents/
├── skills/                    # Project-level Skills (AI-customized)
│   ├── project-agents-context/  # Shared project context
│   ├── project-acceptor/        # Acceptor project guide
│   ├── project-designer/        # Designer project guide
│   ├── project-implementer/     # Implementer project guide
│   ├── project-reviewer/        # Reviewer project guide
│   └── project-tester/          # Tester project guide
├── runtime/                   # Agent runtime state
│   ├── active-agent             # Currently active role
│   ├── acceptor/                # Acceptor workspace
│   ├── designer/                # Designer workspace
│   ├── implementer/             # Implementer workspace
│   ├── reviewer/                # Reviewer workspace
│   └── tester/                  # Tester workspace
├── memory/                    # Memory system
│   ├── PROJECT_MEMORY.md        # Project-level memory
│   ├── index.sqlite             # FTS5 search index
│   └── {role}/                  # Role-specific memory
│       ├── MEMORY.md              # Long-term memory
│       └── diary/                 # Diary memory
├── tasks/                     # Task data
├── task-board.json            # Task board
├── task-board.md              # Human-readable board
├── events.db                  # Audit log
├── jobs.json                  # Cron scheduling config
└── tool-profiles.json         # Tool access control config
```

### 1.3 Your First Task (5-minute walkthrough)

**Step 1: Switch to Acceptor, define requirements**
```
/agent acceptor

I need a user login feature with email/password login and OAuth third-party login.
```

The Acceptor will:
- Create task T-001 (title, description, goal list)
- Example goals: G1 "Email/password login form", G2 "OAuth integration", G3 "JWT token management"

**Step 2: Switch to Designer**
```
/agent designer
```

The Designer will:
- Read T-001's goals
- Output design doc to `.agents/runtime/designer/workspace/design-docs/T-001.md`
- Includes: technical plan, file change list, test specs

**Step 3: Switch to Implementer**
```
/agent implementer
```

The Implementer will:
- Read the design doc
- Code using TDD (write test → red → implement → green → refactor)
- Commit code when done

**Step 4: Switch to Reviewer**
```
/agent reviewer
```

The Reviewer will:
- Review design doc + code changes
- Output review report (CRITICAL/HIGH/MEDIUM/LOW)
- PASS or FAIL

**Step 5: Switch to Tester**
```
/agent tester
```

The Tester will:
- Verify each goal one by one
- Run the test suite
- Mark goals as met/not-met

**Step 6: Switch to Acceptor**
```
/agent acceptor
```

The Acceptor will:
- Check if all goals are MET
- Accept the task (status → accepted)

---

## 2. Core Concepts

### 2.1 Five Agent Roles

| Role | Responsibility | Input | Output |
|------|----------------|-------|--------|
| 🎯 **Acceptor** | Requirement definition + final acceptance | User requirements | Tasks + goal list |
| 📐 **Designer** | Technical solution design | Task goals | Design doc + test specs |
| 💻 **Implementer** | Coding implementation | Design doc | Code + tests |
| 🔍 **Reviewer** | Design + code review | Design doc + code | Review report |
| 🧪 **Tester** | Goal verification + quality check | Code + goals | Verification report |

**Switch roles:**
```
/agent acceptor    # Switch to Acceptor
/agent designer    # Switch to Designer
/agent implementer # Switch to Implementer
/agent reviewer    # Switch to Reviewer
/agent tester      # Switch to Tester
```

### 2.2 FSM State Machine

Tasks are managed through a Finite State Machine (FSM) lifecycle:

```
              ┌──────────────────────────────────────────────┐
              │                                              │
created ──→ designing ──→ implementing ──→ reviewing ──→ testing ──→ accepting ──→ accepted
              │                ↑              │        │
              │                │              │        │
              │                └── rejected ──┘        └── test_failed ──→ implementing
              │                    (review failed)              (test failed)
              └──────────────────────────────────────────────┘
                              (design needs rework)
```

**Status descriptions:**
| Status | Meaning | Responsible Agent |
|--------|---------|-------------------|
| `created` | Task created, awaiting design | Acceptor |
| `designing` | Designing solution | Designer |
| `implementing` | Coding in progress | Implementer |
| `reviewing` | Under review | Reviewer |
| `testing` | Under verification | Tester |
| `accepting` | Awaiting final acceptance | Acceptor |
| `accepted` | Task complete ✅ | — |

**Disallowed transitions (Guard Rules):**
- ❌ Cannot skip review to go directly to testing
- ❌ Cannot jump from testing to acceptance (must pass)
- ❌ Only the corresponding role can advance its status

### 2.3 Tasks and Goals

**Task structure:**
```json
{
  "id": "T-001",
  "title": "User Login Feature",
  "status": "implementing",
  "goals": [
    {"id": "G1", "description": "Email/password login form", "met": false},
    {"id": "G2", "description": "OAuth third-party login integration", "met": false},
    {"id": "G3", "description": "JWT token management", "met": true}
  ]
}
```

**Goal writing principles:**
- Each goal must be verifiable (clear pass/fail criteria)
- Appropriate granularity (not too broad, not too granular)
- User story format: "As XX, I want YY, so that ZZ"

**Good goal:** "Login API returns JWT token containing userId and exp fields"
**Bad goal:** "Implement login feature" (too vague, not verifiable)

### 2.4 Memory System

**Three-layer architecture:**

| Layer | File | Lifecycle | Content |
|-------|------|-----------|---------|
| L1 Long-term | `{role}/MEMORY.md` | Permanent | Core decisions, architecture conventions |
| L2 Diary | `{role}/diary/YYYY-MM-DD.md` | 30-90 days | Daily observations, temporary decisions |
| L3 Project | `PROJECT_MEMORY.md` | Permanent | Tech stack, ADRs, hotspot files |

**Search memory:**
```bash
bash scripts/memory-search.sh "login auth"
bash scripts/memory-search.sh "architecture decision" --role designer --limit 10
bash scripts/memory-search.sh "test strategy" --layer long-term
```

**Output example:**
```
[.agents/memory/implementer/MEMORY.md:15] Project uses **JWT** for auth, token TTL 24h
[.agents/memory/designer/diary/2026-04-07.md:8] Design decision: **OAuth** uses PKCE flow
```

**Auto-promotion (Dreaming):**
- If a diary entry is searched 3+ times across 3+ distinct queries → auto-promoted to MEMORY.md
- 6-signal scoring: Frequency(24%) + Relevance(30%) + Diversity(15%) + Recency(15%) + Stability(10%) + Richness(6%)

---

## 3. Workflow Details

### 3.1 Standard SDLC Pipeline

```
1. Acceptor: Define requirements
   Output: task-board.json (new task + goals)

2. Designer: Design solution
   Input: Task goals
   Output: design-docs/T-xxx.md, test-specs/T-xxx.md

3. Implementer: Code implementation
   Input: Design doc
   Output: Code changes + test code
   Flow: TDD (red → green → refactor)

4. Reviewer: Review
   Input: Design doc + code changes
   Output: review-reports/review-T-xxx.md
   Verdict: PASS → proceed to testing / FAIL → return to implementation

5. Tester: Verification
   Input: Code + goals
   Output: Goals met/not-met
   Verdict: All MET → proceed to acceptance / Any NOT MET → return to implementation

6. Acceptor: Acceptance
   Input: Verification results
   Output: status → accepted
```

### 3.2 Auto-transition

**With auto-transition enabled:**
- Designer completes design → system auto-switches to Implementer
- Implementer completes coding → system auto-switches to Reviewer
- No manual `/agent switch` needed

**Timeout detection:**
| Phase | Timeout Threshold | Timeout Action |
|-------|-------------------|----------------|
| designing | 2 hours | Notify, suggest simplification |
| implementing | 4 hours | Notify, suggest splitting |
| reviewing | 1 hour | Notify |
| testing | 2 hours | Notify |
| accepting | 1 hour | Notify |

### 3.3 Parallel Execution

**Multiple Implementers in parallel:**
```
Coordinator (Implementer)
├── Sub-Agent 1: T-024 (memory-index.sh)
├── Sub-Agent 2: T-025 (memory-search.sh)
└── Sub-Agent 3: T-026 (lifecycle management)
```

**Use cases:**
- Multiple independent tasks simultaneously in implementing status
- Large tasks splittable into sub-tasks that don't modify the same files
- Reviewing multiple unrelated file changes

**Constraints:**
- Each sub-agent operates on different files (avoid conflicts)
- task-board.json is only modified by the coordinator
- After sub-agents finish, the coordinator consolidates and verifies

### 3.4 Worktree Isolated Parallelism

When multiple tasks modify the same files, use Git Worktree for full isolation:

```bash
# Create independent worktrees
/agent-worktree create T-042
/agent-worktree create T-043

# View all active worktrees
/agent-worktree list

# Develop independently in separate terminals
cd ../project--T-042 && /agent implementer
cd ../project--T-043 && /agent implementer

# Merge back to main when done
/agent-worktree merge T-042

# Start multi-task tmux session (one window per task)
bash scripts/team-session.sh --worktree --tasks T-042,T-043
```

**Shared vs Isolated:**
| Resource | Approach |
|----------|----------|
| task-board.json | Symlink → main worktree |
| events.db | Symlink → main worktree |
| inbox/memory/docs | Independent per worktree |
| Source code | Fully isolated (independent branches) |
| Skills/Hooks | Auto-inherited (global directory) |

---

## 4. Advanced Features

### 4.1 Hook System

**15+ Hook points:**

| Hook | Trigger | Purpose |
|------|---------|---------|
| `session-start` | Session begins | Load state |
| `pre-tool-use` | Before tool invocation | Boundary check |
| `post-tool-use` | After tool invocation | Audit logging |
| `staleness-check` | Periodic | Timeout detection |
| `before-switch` | Before Agent switch | Validate legitimacy |
| `after-switch` | After Agent switch | Inject context |
| `before-task-create` | Before task creation | Format/duplicate validation |
| `after-task-status` | After status change | Notification/memory persistence |
| `before-memory-write` | Before memory write | Dedup/path validation |
| `after-memory-write` | After memory write | Index update |
| `before-compaction` | Before context compaction | Auto flush |
| `on-goal-verified` | On goal verification | Progress update |
| `security-scan` | Security scan | OWASP check |

**Hook control semantics:**
```json
{"block": true, "reason": "Reviewer cannot modify source code"}
{"requireApproval": true, "message": "Task has incomplete goals, confirm acceptance?"}
{"allow": true}
```

**Custom Hook:**
```bash
#!/usr/bin/env bash
# hooks/my-custom-hook.sh
set -euo pipefail
INPUT=$(cat)  # Read stdin JSON
# Your logic...
echo '{"allow": true}'
```

### 4.2 Tool Access Control

**Role tool whitelist (`.agents/tool-profiles.json`):**

| Role | Writable | Read-only |
|------|----------|-----------|
| Acceptor | None (read-only) | All files |
| Designer | docs/, .agents/runtime/designer/ | skills/, hooks/, src/ |
| Implementer | All source code | task-board.json |
| Reviewer | .agents/runtime/reviewer/, docs/review.md | skills/, hooks/, src/ |
| Tester | tests/, .agents/runtime/tester/ | skills/, hooks/ |

### 4.3 Cron Scheduling

**Configure `.agents/jobs.json`:**
```json
{
  "jobs": [
    {
      "id": "staleness-check",
      "schedule": "*/30 * * * *",
      "action": "check-staleness",
      "enabled": true,
      "description": "Check stale tasks every 30 minutes"
    },
    {
      "id": "daily-summary",
      "schedule": "0 9 * * *",
      "action": "generate-report",
      "enabled": true,
      "description": "Generate progress summary daily at 9 AM"
    }
  ]
}
```

**External cron integration:**
```bash
# Add to system crontab
crontab -e
*/5 * * * * cd /path/to/project && bash scripts/cron-scheduler.sh --run
```

**Webhook triggers:**
```bash
bash scripts/webhook-handler.sh github-push '{"branch":"main"}'
bash scripts/webhook-handler.sh ci-failure '{"build":123}'
```

### 4.4 Living Documentation System

6 project-level documents, incrementally maintained by each role:

| Document | Maintainer | Content |
|----------|------------|---------|
| `docs/requirement.md` | Acceptor | Accumulated requirements |
| `docs/design.md` | Designer | Accumulated design decisions |
| `docs/implementation.md` | Implementer | Implementation notes |
| `docs/review.md` | Reviewer | Review findings |
| `docs/test-spec.md` | Tester | Test specifications |
| `docs/acceptance.md` | Acceptor | Acceptance records |

### 4.5 Context Engine

**Context budget allocation:**

| Source | Reviewer | Implementer | Designer |
|--------|----------|-------------|----------|
| System prompt | 5k | 5k | 5k |
| Project context | 10k | 10k | 15k |
| Task context | 20k | 15k | 20k |
| Code context | 50k | 40k | 10k |
| Memory Top-6 | 10k | 5k | 10k |
| Conversation history | 85k | 105k | 120k |

**Role bootstrap injection order:**
1. Global SKILL.md (role workflow)
2. Project-level SKILL.md (project-specific commands)
3. Current task goals + design doc
4. Memory search Top-6
5. Upstream Agent handoff message
6. Project context

---

## 5. Command Reference

### Quick Reference

| Action | Command |
|--------|---------|
| Switch role | `/agent <role>` |
| Initialize project | "Initialize Agent system" |
| View task board | View `.agents/task-board.json` |
| Search memory | `bash scripts/memory-search.sh "keyword"` |
| Rebuild index | `bash scripts/memory-index.sh --force` |
| Run tests | `bash tests/run-all.sh` |
| Check installation | `bash install.sh --check` |
| View schedule | `bash scripts/cron-scheduler.sh --check` |
| Run schedule | `bash scripts/cron-scheduler.sh --run` |
| Webhook | `bash scripts/webhook-handler.sh <event> [json]` |

---

## 6. Best Practices

### 6.1 Task Decomposition

- **Granularity**: 2-6 goals per task, estimated 1-4 hours to complete
- **Independence**: Each task should be independently acceptable
- **Verifiable goals**: Each goal must have clear pass/fail criteria

### 6.2 Memory Management

- Important decisions → write to MEMORY.md (long-term)
- Daily observations → auto-written to diary (short-term)
- Project-level conventions → write to PROJECT_MEMORY.md
- Periodically run `bash scripts/memory-index.sh` to update the index

### 6.3 FAQ

**Q: Context lost after Agent switch?**
A: The memory system auto-loads relevant memories. Ensure the current Agent writes key decisions before switching.

**Q: Review keeps failing?**
A: Check the Reviewer's severity levels. CRITICAL/HIGH must be fixed; MEDIUM/LOW are optional.

**Q: How to skip a phase?**
A: The FSM does not allow skipping. If truly needed, manually modify task status (not recommended).

---

## 7. Configuration Reference

### hooks.json
```json
{
  "hooks": {
    "SessionStart": [{"matcher": "*", "hooks": [{"type": "command", "command": "hooks/xxx.sh"}]}],
    "PreToolUse": [...],
    "PostToolUse": [...],
    "AgentSwitch": [...],
    "TaskCreate": [...],
    "TaskStatusChange": [...],
    "MemoryWrite": [...],
    "Compaction": [...],
    "GoalVerified": [...]
  }
}
```

### task-board.json
```json
{
  "version": 27,
  "tasks": [
    {
      "id": "T-001",
      "title": "Task Title",
      "status": "accepted",
      "goals": [{"id": "G1", "description": "Goal description", "met": true}],
      "created": "2026-04-07T12:00:00"
    }
  ]
}
```

### jobs.json
```json
{
  "jobs": [
    {
      "id": "job-id",
      "schedule": "cron expression",
      "action": "action name",
      "enabled": true,
      "description": "Description"
    }
  ]
}
```

---

## Version Info

- **Framework version**: v3.3.1
- **Skills**: 18 (globally installed, includes shared + role-specific, per-Agent isolation)
- **Hooks**: 13 shell scripts / 9 event types
- **Scripts**: 8 utility scripts
- **Workflow modes**: 2 (Simple + 3-Phase)
- **Phase 1-13**: All complete ✅

---

## 8. 3-Phase Engineering Closed Loop Guide

> v3.0 new feature — for complex features, hardware/firmware, safety-critical, and multi-team projects

### 8.1 Initialize a 3-Phase Project

In the project root directory, tell the AI assistant:

```
Initialize Agent system
```

When prompted to choose a workflow mode, select **2 (3-Phase)**:

```
🔄 Please choose a workflow mode:
  1. Simple (linear)
  2. 3-Phase (three-phase engineering closed loop)
Select [1/2]: 2
```

After initialization, additionally generates:
- `.agents/orchestrator/run.sh` — Orchestrator daemon
- `.agents/prompts/` — 16 step prompt templates
- `task-board.json` with `default_workflow_mode: "3phase"`

### 8.2 Start the Orchestrator

After creating a task, use the orchestrator to automatically drive the full 3-Phase flow:

```bash
# Start orchestrator daemon (runs in background)
nohup bash .agents/orchestrator/run.sh T-001 &

# Check running status
bash .agents/orchestrator/run.sh T-001 --status

# View live logs
tail -f .agents/orchestrator/logs/T-001-*.log

# Stop orchestrator
bash .agents/orchestrator/run.sh T-001 --stop
```

The orchestrator will automatically:
1. Phase 1: Sequentially invoke acceptor → designer → tester → designer → reviewer
2. Phase 2: Launch implementer + tester + reviewer in parallel, then check CI after convergence
3. Phase 3: Deploy → regression test → functional test → log analysis → documentation

### 8.3 Configure External Systems

During initialization or by editing `.agents/orchestrator/run.sh`, configure pluggable external systems:

**CI system configuration:**
```bash
# GitHub Actions
CI_SYSTEM="github-actions"
CI_URL="https://github.com/org/repo/actions"
CI_STATUS_CMD="gh run list --limit 1 --json status"
CI_TRIGGER_CMD="gh workflow run ci.yml"

# Jenkins
CI_SYSTEM="jenkins"
CI_URL="https://jenkins.example.com/job/my-project"
CI_STATUS_CMD="curl -s ${CI_URL}/lastBuild/api/json | jq .result"
CI_TRIGGER_CMD="curl -X POST ${CI_URL}/build"

# GitLab CI
CI_SYSTEM="gitlab-ci"
CI_URL="https://gitlab.com/org/repo/-/pipelines"
CI_STATUS_CMD="glab ci status"
CI_TRIGGER_CMD="glab ci run"
```

**Code review system configuration:**
```bash
# GitHub PR
REVIEW_SYSTEM="github-pr"
REVIEW_CMD="gh pr create --fill"
REVIEW_STATUS_CMD="gh pr checks"

# Gerrit
REVIEW_SYSTEM="gerrit"
REVIEW_CMD="git review"
REVIEW_STATUS_CMD="ssh gerrit gerrit query --current-patch-set status:open"

# GitLab MR
REVIEW_SYSTEM="gitlab-mr"
REVIEW_CMD="glab mr create --fill"
REVIEW_STATUS_CMD="glab mr view"
```

**Device/environment configuration:**
```bash
# Local Docker
DEVICE_TYPE="localhost"
DEPLOY_CMD="docker compose up -d"
LOG_CMD="docker compose logs --tail=200"
BASELINE_CMD="curl -sf http://localhost:8080/health"

# Remote staging
DEVICE_TYPE="staging"
DEPLOY_CMD="ssh staging 'cd /app && git pull && systemctl restart app'"
LOG_CMD="ssh staging 'journalctl -u app --no-pager -n 200'"
BASELINE_CMD="curl -sf https://staging.example.com/health"

# Real hardware
DEVICE_TYPE="hardware"
DEPLOY_CMD="scp build/firmware.bin device:/tmp/ && ssh device 'flash /tmp/firmware.bin'"
LOG_CMD="ssh device 'dmesg --follow'"
BASELINE_CMD="ssh device 'run-selftest'"
```

### 8.4 Full Example: 3-Phase Task End-to-End

```bash
# 1. Initialize project (select 3-Phase mode)
# Tell AI assistant "Initialize Agent system", select mode 2

# 2. Switch to Acceptor, create task
# /agent acceptor
# "Create a new SFP module driver refactoring task, needs C++20 coroutine support"

# 3. Start orchestrator
bash .agents/orchestrator/run.sh T-001

# 4. Monitor progress
watch -n 10 'jq ".tasks[0] | {status, phase, step, feedback_loops, parallel_tracks}" .agents/task-board.json'

# 5. View feedback loop history
jq '.tasks[0].feedback_history' .agents/task-board.json

# 6. If task is blocked (feedback loop limit exceeded)
# /agent acceptor
# "unblock T-001, reset feedback counter"
# Then restart orchestrator

# 7. After task completes, view full logs
ls -la .agents/orchestrator/logs/T-001-*
```

### 8.5 Mixing 3-Phase and Simple Modes

The same project can have both Simple and 3-Phase tasks:
- `T-001` (`workflow_mode: "3phase"`) — driven by orchestrator
- `T-002` (`workflow_mode: "simple"`) — driven by manual /agent switching

The FSM automatically selects valid transition rules based on each task's `workflow_mode` field.

---

> 📖 More info: [GitHub](https://github.com/cintia09/multi-agent-framework) | [CONTRIBUTING.md](../CONTRIBUTING.md) | [CHANGELOG.md](../CHANGELOG.md)

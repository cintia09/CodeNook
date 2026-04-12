---
name: agent-init
description: "Initialize the project's Agent collaboration system. Say 'Initialize Agent system' to trigger. Detects project tech stack, creates runtime directories and project-level skills under .agents/."
---

# Project Agent Initialization

## Prerequisites
- Current directory is the project root (has a git repo or package.json, etc.)
- Global skills installed (`~/.claude/skills/agent-*/SKILL.md`)
- Global agents installed (`~/.claude/agents/*.agent.md`)

## Execution Steps

### 0. Check If Already Initialized
```bash
ls .agents/task-board.json 2>/dev/null
```
- **Exists**: Output "⚠️ Agent system already initialized, skipping." **Do not overwrite any files**.
- **Does not exist**: Perform fresh initialization (Step 1-7).

### 1. Gather Context Information

#### 1a. Detect Project Tech Stack
```bash
ls package.json Cargo.toml requirements.txt go.mod pom.xml Gemfile composer.json *.csproj *.sln Package.swift pubspec.yaml build.gradle setup.py pyproject.toml CMakeLists.txt Makefile 2>/dev/null
ls next.config* nuxt.config* angular.json vue.config* Caddyfile nginx.conf webpack.config* vite.config* tsconfig.json .babelrc tailwind.config* 2>/dev/null
ls jest.config* playwright.config* pytest.ini vitest.config* .rspec karma.conf* cypress.config* phpunit.xml 2>/dev/null
ls .github/workflows/*.yml .gitlab-ci.yml .circleci/config.yml Jenkinsfile .travis.yml bitbucket-pipelines.yml 2>/dev/null
ls Dockerfile docker-compose* k8s/ fly.toml render.yaml vercel.json netlify.toml serverless.yml samconfig.toml app.yaml Procfile 2>/dev/null
ls lerna.json pnpm-workspace.yaml nx.json turbo.json rush.json 2>/dev/null
head -5 README.md 2>/dev/null
```

#### 1b. Read Project-Level Instructions
```bash
cat CLAUDE.md 2>/dev/null
cat .github/copilot-instructions.md 2>/dev/null
```

#### 1c. Classify Project Type

Based on Step 1a detection results, classify the project:

| Detection Features | Project Type | Identifier |
|-------------------|-------------|------------|
| Package.swift / .xcodeproj / SwiftUI | iOS/macOS Native | `ios` |
| next.config / nuxt.config / vue.config / angular.json | Frontend Web | `frontend` |
| package.json + no frontend framework / go.mod / pom.xml | Backend Service | `backend` |
| Cargo.toml / CMakeLists.txt / Makefile (C/C++) | Systems-Level | `systems` |
| requirements.txt + torch/tensorflow/transformers | AI/ML | `ai-ml` |
| Dockerfile + k8s/ / serverless.yml | DevOps/Infrastructure | `devops` |
| Other / Mixed | General | `general` |

Record in Step 5a's project-agents-context: `project_type: "<type>"`

#### 1d. HITL Configuration (Enabled by Default)

HITL approval gate is enabled by default, using the `local-html` platform. Automatically written to `.agents/config.json` during initialization:
```json
{
  "hitl": {
    "enabled": true,
    "platform": "local-html"
  }
}
```

If the user is in a Docker/SSH headless environment, automatically switch to `terminal` platform:
```bash
# Detect Docker/headless environment
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null || [ -z "$DISPLAY" -a -z "$WAYLAND_DISPLAY" -a "$(uname)" != "Darwin" ]; then
  HITL_PLATFORM="terminal"
else
  HITL_PLATFORM="local-html"
fi
```

#### 1e. Read Global Agent Profiles, Skills & Rules

Scan all global resources to build complete context:

```bash
# Agent Profiles (5 total, with skills: isolation list)
for f in acceptor designer implementer reviewer tester; do
  cat ~/.claude/agents/${f}.agent.md 2>/dev/null || cat ~/.copilot/agents/${f}.agent.md 2>/dev/null
done

# All 20 Skills (read only frontmatter + first 20 lines summary to avoid context overflow)
for d in ~/.claude/skills/agent-*/SKILL.md; do
  head -20 "$d" 2>/dev/null
done

# Global Rules
for r in ~/.claude/rules/*.md; do
  cat "$r" 2>/dev/null
done
```

> Note: Each agent profile's `skills:` frontmatter defines the list of skills that role is allowed to invoke (per-agent isolation).

#### 1f. Detect Platform

```bash
# Detect current running platform
if [ -d ~/.claude ]; then PLATFORM="claude-code"; fi
if [ -d ~/.copilot ]; then PLATFORM="${PLATFORM:+$PLATFORM+}copilot-cli"; fi
```

### 2. Create Directory Structure
```bash
mkdir -p .agents/skills/project-{agents-context,acceptor,designer,implementer,reviewer,tester}
mkdir -p .agents/tasks .agents/memory .agents/docs
mkdir -p .agents/runtime/{acceptor,designer,implementer,reviewer,tester}/workspace
mkdir -p .agents/runtime/designer/workspace/{research,design-docs,test-specs}
mkdir -p .agents/runtime/acceptor/workspace/{requirements,acceptance-docs,acceptance-reports}
mkdir -p .agents/runtime/reviewer/workspace/review-reports
mkdir -p .agents/runtime/tester/workspace/{test-cases,test-screenshots}
mkdir -p docs
for doc in requirement design test-spec implementation review acceptance; do
  [ -f "docs/${doc}.md" ] || cp ~/.claude/skills/agent-init/templates/docs/${doc}.md docs/ 2>/dev/null || true
done
```

### 3. Initialize State Files

Create `inbox.json` for each Agent:
```json
// .agents/runtime/<agent>/inbox.json
{"messages":[]}
```

#### 3b. Initialize events.db
```bash
sqlite3 .agents/events.db <<'SQL'
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL,
  event_type TEXT NOT NULL, agent TEXT, task_id TEXT, tool_name TEXT,
  detail TEXT, created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_agent ON events(agent);
CREATE INDEX IF NOT EXISTS idx_events_task ON events(task_id);
SQL
```
Event types: `session_start` | `tool_use` | `task_board_write` | `state_change` | `agent_switch` | `message_sent`

### 4. Create Empty Task Board
- **`.agents/task-board.json`**: `{"version": 0, "tasks": []}`
- **`.agents/task-board.md`**: Markdown table (`| ID | Title | Status | Assignee | Priority | Updated |`), auto-generated — do not edit manually

### 5. Generate Project-Level Skills (AI Customized)

> ⚠️ **Generated** by AI based on Step 1 context, not copied from templates.
> Global skills define "how to do it", project skills supplement "what tools to use".

**General requirements**: YAML frontmatter header, Markdown format, project-relative paths, actual commands.

#### 5a. `project-agents-context/SKILL.md` — Shared Context
Must include: Project info (name/description/repo) | Tech stack | `project_type` | Common commands table | Directory structure | Branch strategy

#### 5b. `project-acceptor/SKILL.md` — Project-Level Acceptance
Must include: Business background | Acceptance baseline (tests/build/lint/coverage) | Acceptance process | Quality red lines

#### 5c. `project-designer/SKILL.md` — Project-Level Design
Must include: Existing architecture | Technical constraints (language version/framework/compatibility) | Design document template | API/data conventions

#### 5d. `project-implementer/SKILL.md` — Project-Level Development
Must include: Development commands table | Coding standards (indentation/quotes/naming/commits) | Dependency management | TDD workflow

#### 5e. `project-reviewer/SKILL.md` — Project-Level Review
Must include: Review checklist (build/tests/lint/security/style/test coverage) | Project-specific rules | Review report template

#### 5f. `project-tester/SKILL.md` — Project-Level Testing
Must include: Test framework | Test commands table | Test file organization | Test strategy | Test environment

> **Project type adaptation**: Customize each skill's content based on the `project_type` detected in Step 1c:
>
> | Project Type | Tester Focus | Implementer Focus | Designer Focus |
> |-------------|-------------|-------------------|----------------|
> | `ios` | XCTest, UI Testing, SwiftUI Previews | Xcode, Swift Package Manager, SwiftUI/UIKit | MVC/MVVM, Core Data, App Lifecycle |
> | `frontend` | Playwright/Cypress, Jest/Vitest, RTL | npm/pnpm, ESLint, TypeScript strict | Component architecture, state management, API layer design |
> | `backend` | API integration tests, DB migration tests, load tests | ORM, middleware, containerization | Microservices/monolith, data models, auth |
> | `systems` | Unit + integration tests, Valgrind/Sanitizers | CMake/Cargo, memory safety, performance profiling | Module interfaces, memory model, thread safety |
> | `ai-ml` | Model accuracy/recall validation, dataset split tests | Jupyter→.py, training pipeline, GPU resources | Model architecture, data pipeline, experiment tracking |
> | `devops` | Terraform plan validation, container health checks | IaC, CI/CD pipeline, monitoring/alerting | Infrastructure topology, security groups, disaster recovery |

### 5g. Project-Level Hooks (Optional)
If project-level hook overrides are needed:
```bash
mkdir -p .agents/hooks
for hook in agent-session-start.sh agent-pre-tool-use.sh agent-post-tool-use.sh agent-staleness-check.sh; do
  [ -f ~/.claude/hooks/"$hook" ] && cp ~/.claude/hooks/"$hook" .agents/hooks/ && chmod +x .agents/hooks/"$hook"
done
```

### 5h. (Removed — 3-Phase workflow merged into unified process)

> 3-Phase engineering loop has been unified into the linear workflow. Orchestrator daemon is still optionally available, but a separate 3-Phase initialization is no longer needed.

### 6. Create .agents/.gitignore
```
runtime/*/inbox.json
orchestrator/logs/
orchestrator/daemon.pid
!runtime/*/workspace/.gitkeep
```

### 7. Generate/Update Project-Level Instructions

> Combine context gathered in Step 1 + global framework information to generate project-level configuration files.
> If the file already exists, **append** framework-related content (do not overwrite existing content).

#### 7a. CLAUDE.md (Claude Code Project Configuration)

Generate or append to project root `CLAUDE.md`:

```markdown
# Agent Framework Configuration

## Framework Info
- Multi-Agent Framework v3.4.x
- 5 Agent roles | 20 Skills | 13 Hooks | Unified FSM

## ⚡ Role Switch Trigger Rules (MANDATORY)
When user message matches the following patterns, immediately perform role switch (invoke agent-switch skill):
- `/agent <name>` | `switch to <role>`
- `act as <role>`
Roles: acceptor, designer, implementer, reviewer, tester
Do not ask for confirmation — execute the switch process directly.

## ⛔ Role Permission Self-Check (MANDATORY — execute before each operation)
After switching roles, self-check permissions before each file operation. Violation → refuse + suggest role switch.
| Role | Prohibited |
|------|-----------|
| acceptor | Writing/modifying source code, modifying design documents |
| designer | Writing implementation code, running tests |
| implementer | Modifying requirements, skipping review |
| reviewer | Modifying code, executing rm/delete |
| tester | Modifying source code, modifying design |

## Global Resources
- Agent Profiles: ~/.claude/agents/*.agent.md (with skills: per-agent isolation)
- Skills: ~/.claude/skills/agent-*/ (20 total, two-level loading: summary list + on-demand full text)
- Hooks: ~/.claude/hooks/ (13 Shell scripts)
- Rules: ~/.claude/rules/ (agent-workflow, commit-standards, security)

## Project Tech Stack
<Fill based on Step 1a detection results>

## Common Commands
| Command | Description |
|---------|-------------|
| /agent acceptor | Switch to acceptor role |
| switch to acceptor | Same (natural language trigger) |
| /agent-init | Initialize Agent system |
| /agent-task-board | View task board |
| /agent-fsm | View FSM state machine |

## Agent Interaction Rules (MANDATORY)
At the end of each response, must ask the user about next steps based on the current Agent role:
- 🎯 Acceptor: Ask about requirements confirmation, task priorities, acceptance timeline
- 🏗️ Designer: Ask about architecture choices, technical approach preferences, design confirmation
- 💻 Implementer: Ask about implementation strategy, test scope, whether to continue to next Goal
- 🔍 Reviewer: Ask about review focus, whether to accept modification suggestions
- 🧪 Tester: Ask about test scope, whether additional test cases are needed

## Project Standards
<Preserve existing CLAUDE.md content from Step 1b>
```

#### 7b. .github/copilot-instructions.md (Copilot CLI Project Configuration)

```bash
mkdir -p .github
```

Generate or append to `.github/copilot-instructions.md`, with content corresponding to 7a, but with path replacements for Copilot:
- `~/.claude/` → `~/.copilot/`
- `hooks.json` → `hooks-copilot.json`

#### 7c. Update .gitignore

Ensure the entire Agent system directory is ignored (user projects should not track .agents/):
```bash
# Check if project .gitignore already excludes .agents/
grep -q '^\.agents/' .gitignore 2>/dev/null || cat >> .gitignore << 'GITIGNORE'

# Multi-Agent Framework (runtime state, not tracked)
.agents/
GITIGNORE
```

### 8. Output Summary
```
✅ Agent system initialized
━━━━━━━━━━━━━━━━━━━━━━━
Project: <name> | Tech Stack: <detected> | Workflow: Unified Linear
Skills: 6 project + 20 global | Runtime: 5 agents | Platform: <Claude Code/Copilot/Both>
CLAUDE.md: ✅ Generated | copilot-instructions.md: ✅ Generated
Next step: /agent acceptor to start collecting requirements
```

# Design Proposal: Worktree-Based Parallel Task Development

> Task ID: T-WORKTREE | Status: Designing | Priority: HIGH

## 1. Problem Statement

Currently all tasks share the same working directory. When developing multiple tasks simultaneously:
- Two tasks modifying the same file → **file conflicts**
- Agent cannot distinguish which changes belong to which task → **context confusion**
- Only serial development possible, must finish one before starting next → **throughput bottleneck**

## 2. Solution: Git Worktree Isolation

### Core Concept

```
project/                              # Main worktree (main branch)
├── .agents/
│   ├── task-board.json               # ← Shared board (visible to all worktrees)
│   ├── events.db                     # ← Shared audit log
│   └── runtime/                      # ← Main worktree runtime
│
├── src/                              # Main branch code

project--T-042/                       # Worktree for T-042 (task/T-042 branch)
├── .agents/
│   ├── task-board.json → symlink     # Points to main worktree
│   ├── events.db → symlink           # Points to main worktree
│   └── runtime/                      # Independent runtime (inbox, memory)
│
├── src/                              # T-042 independent changes

project--T-043/                       # Worktree for T-043
├── ...                               # Same as above
```

### Lifecycle

```
1. Create task    →  git worktree add ../project--T-042 -b task/T-042
2. Development    →  In worktree: /agent implementer → independent coding
3. Review phase   →  Same worktree: /agent reviewer → review diff
4. Merge on done  →  git checkout main && git merge task/T-042
5. Cleanup        →  git worktree remove ../project--T-042
```

## 3. Shared vs Isolated Resource Matrix

| Resource | Sharing Method | Reason |
|----------|---------------|--------|
| `task-board.json` | **Symlink** → main worktree | Global board, visible to all tasks |
| `events.db` | **Symlink** → main worktree | Unified audit log |
| `runtime/<agent>/inbox.json` | **Isolated** (independent per worktree) | Each task's message queue is independent |
| `memory/T-NNN-*.json` | **Isolated** (in each worktree's .agents/) | Task memory bound to task |
| `docs/T-NNN/` | **Isolated** (in each worktree's .agents/) | Docs bound to task |
| Skills (global) | **Auto-inherited** (same user directory) | ~/.claude/skills/ not in project |
| Hooks (global) | **Auto-inherited** | ~/.claude/hooks/ not in project |
| Source code | **Fully isolated** (independent branch) | This is worktree's core value |

## 4. Components to Add/Modify

### 4a. `agent-worktree` skill (New)

Skill for managing worktree lifecycle:

```
/agent-worktree create T-042        # Create worktree + branch + symlinks
/agent-worktree list                # List all active worktrees
/agent-worktree switch T-042        # cd to corresponding worktree
/agent-worktree merge T-042         # Merge back to main + cleanup
/agent-worktree status              # git diff stat for each worktree
```

### 4b. `team-session.sh` Enhancement

```bash
# Existing: Same-directory tmux split panes
bash scripts/team-session.sh --agents implementer,tester --task T-042

# New: Worktree mode — one tmux window per task
bash scripts/team-session.sh --worktree --tasks T-042,T-043
```

Each tmux window `cd`s to the corresponding worktree directory; agents work in isolated environments.

### 4c. `auto-dispatch.sh` Modification

Cross-worktree message routing:

```bash
# Current: Write to .agents/runtime/<agent>/inbox.json (same directory)
# New: If task has a worktree, write to that worktree's inbox
WORKTREE_DIR=if [ -n "" ]; then
  TARGET_INBOX="\/.agents/runtime/\/inbox.json"
fi
```

### 4d. task-board.json Extended Fields

```json
{
  "id": "T-042",
  "title": "User Authentication",
  "status": "implementing",
  "worktree": {
    "path": "../project--T-042",
    "branch": "task/T-042",
    "created_at": "2025-01-15T10:00:00Z"
  }
}
```

## 5. Concurrency Safety

| Risk | Scenario | Solution |
|------|----------|----------|
| task-board.json write contention | Two worktrees updating board simultaneously | Existing mkdir-based atomic lock ✅ |
| events.db write contention | Two tasks writing audit log simultaneously | SQLite WAL mode + existing framework lock ✅ |
| Git conflicts | Two tasks modifying the same file | Resolve manually at merge time (standard Git workflow) |
| Stale branch | Worktree branch behind main | Rebase before merge: `git rebase main` |

## 6. Claude Code / Copilot CLI Adaptation

| Scenario | Claude Code | Copilot CLI |
|----------|------------|-------------|
| Multi-window | Each terminal `cd`s to different worktree, each opens a `claude` | Each terminal opens a `copilot` |
| Context | Auto-loads .agents/ from worktree directory | Same |
| Skills | Global ~/.claude/skills/ auto-inherited | Global ~/.copilot/skills/ auto-inherited |
| Hooks | Global hooks auto-applied | Same |

> **Key Advantage**: The worktree approach is fully compatible with existing platforms and requires no special Claude Code/Copilot support. Each worktree is simply a regular Git working directory.

## 7. User Workflow Example

```bash
# 1. Create two parallel tasks
/agent acceptor
"Create task T-042: User Authentication System"
"Create task T-043: Payment Integration"

# 2. Create worktree for each task
/agent-worktree create T-042
/agent-worktree create T-043

# 3. Develop T-042 in Terminal 1
cd ../project--T-042
/agent implementer
"Implement T-042 login functionality"

# 4. Simultaneously develop T-043 in Terminal 2
cd ../project--T-043
/agent implementer
"Implement T-043 payment API"

# 5. Both tasks progress independently, no interference

# 6. Merge T-042 on completion
/agent-worktree merge T-042
# → git merge task/T-042 into main
# → Cleanup worktree

# 7. T-043 rebases onto latest main and continues
cd ../project--T-043 && git rebase main
```

## 8. Implementation Plan

| Phase | Content | Change Size |
|-------|---------|-------------|
| P1 | `agent-worktree` skill (create/list/merge/status) | New ~200 lines |
| P2 | `team-session.sh` --worktree mode | Modify ~50 lines |
| P3 | `auto-dispatch.sh` cross-worktree routing | Modify ~20 lines |
| P4 | task-board.json worktree field + FSM awareness | Modify ~30 lines |
| P5 | Documentation + tests | New ~100 lines |

Total: ~400 lines added/modified

## 9. Out of Scope

- ❌ No automatic rebase/merge — conflict resolution is human-decided
- ❌ No Git behavior modifications — purely leverages native `git worktree` functionality
- ❌ Not mandatory — simple tasks continue development in main directory
- ❌ No cross-machine sync — worktree is a local concept

---

> 📝 Designer: Copilot | Review Status: Pending Review

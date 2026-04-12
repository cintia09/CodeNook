---
name: agent-worktree
description: "Git Worktree parallel task management. Creates an isolated working directory and branch per task. Use when creating parallel tasks, managing worktrees, or merging completed task branches."
---

# Skill: Git Worktree — Parallel Task Management

Pure Git Worktree operations. Each task gets an isolated working directory and branch.

> ⚠️ This skill only handles git worktree operations — it does not initialize the `.agents/` system.

## Commands

### create — Create Worktree

```bash
TASK_ID="$1"                    # e.g. T-042
PROJECT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WORKTREE_DIR="${PROJECT_DIR}/../${PROJECT_NAME}--${TASK_ID}"
BRANCH_NAME="task/${TASK_ID}"

git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"
```

Output:
```
✅ Worktree created
━━━━━━━━━━━━━━━━━━
Task: T-042 | Branch: task/T-042
Directory: ../project--T-042
Next: cd ../project--T-042
```

### list — List Active Worktrees

```bash
git worktree list
```

### status — Worktree Status Overview

```bash
echo "📊 Worktree Status:"
git worktree list | while read -r dir commit branch; do
  branch="${branch//[\[\]]/}"
  if [[ "$branch" == task/* ]]; then
    task_id="${branch#task/}"
    changed=$(cd "$dir" && git diff --stat HEAD | tail -1 || echo "clean")
    ahead=$(cd "$dir" && git rev-list --count main..HEAD 2>/dev/null || echo "0")
    behind=$(cd "$dir" && git rev-list --count HEAD..main 2>/dev/null || echo "0")
    echo "  $task_id ($branch): $changed | ↑${ahead} ↓${behind} vs main"
  fi
done
```

### merge — Merge & Cleanup

```bash
TASK_ID="$1"
PROJECT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WORKTREE_DIR="${PROJECT_DIR}/../${PROJECT_NAME}--${TASK_ID}"
BRANCH_NAME="task/${TASK_ID}"

# 1. Return to main worktree and merge
cd "$PROJECT_DIR"
git merge "$BRANCH_NAME" --no-ff -m "Merge task/${TASK_ID}"

# 2. Cleanup worktree
git worktree remove "$WORKTREE_DIR" --force
git branch -d "$BRANCH_NAME"
```

Output:
```
✅ Merge complete
━━━━━━━━━━━━━━━━
Task: T-042 | Branch: task/T-042 → main
Worktree: cleaned up ✅
```

## Use Cases

| Scenario | Command |
|----------|---------|
| Parallel feature development | `create T-042` + `create T-043` |
| Emergency hotfix | `create T-FIX-001` |
| A/B approach comparison | Create two worktrees for the same requirement |

## Constraints

- Rebase before merging: `cd ../project--T-042 && git rebase main`
- Worktree directory naming: `<project-name>--<task-id>`

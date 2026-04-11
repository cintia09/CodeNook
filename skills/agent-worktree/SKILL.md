---
name: agent-worktree
description: "Git Worktree 并行任务管理: 为每个任务创建独立工作目录和分支。Use when creating parallel tasks, managing worktrees, or merging completed task branches."
---

# Skill: Agent Worktree — 并行任务管理

基于 Git Worktree 的并行任务开发。每个任务获得独立的工作目录和分支，互不干扰。

## 命令

### create — 创建 Worktree

为指定任务创建独立工作目录:

```bash
TASK_ID="$1"                    # e.g. T-042
PROJECT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WORKTREE_DIR="${PROJECT_DIR}/../${PROJECT_NAME}--${TASK_ID}"
BRANCH_NAME="task/${TASK_ID}"

# 1. 创建 worktree + 分支
git worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"

# 2. 初始化 .agents/ (隔离部分)
mkdir -p "$WORKTREE_DIR/.agents/runtime"/{acceptor,designer,implementer,reviewer,tester}/workspace
mkdir -p "$WORKTREE_DIR/.agents/memory"
mkdir -p "$WORKTREE_DIR/.agents/docs/${TASK_ID}"

# 3. 初始化 inbox.json
for agent in acceptor designer implementer reviewer tester; do
  echo '{"messages":[]}' > "$WORKTREE_DIR/.agents/runtime/${agent}/inbox.json"
done

# 4. Symlink 共享资源 → 主 worktree
ln -sf "$PROJECT_DIR/.agents/task-board.json" "$WORKTREE_DIR/.agents/task-board.json"
ln -sf "$PROJECT_DIR/.agents/task-board.md" "$WORKTREE_DIR/.agents/task-board.md" 2>/dev/null
ln -sf "$PROJECT_DIR/.agents/events.db" "$WORKTREE_DIR/.agents/events.db"

# 5. 更新 task-board.json — 添加 worktree 字段
jq --arg id "$TASK_ID" --arg path "$WORKTREE_DIR" --arg branch "$BRANCH_NAME" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '.tasks = [.tasks[] | if .id == $id then . + {"worktree": {"path": $path, "branch": $branch, "created_at": $ts}} else . end]' \
  "$PROJECT_DIR/.agents/task-board.json" > "$PROJECT_DIR/.agents/task-board.json.tmp" \
  && mv "$PROJECT_DIR/.agents/task-board.json.tmp" "$PROJECT_DIR/.agents/task-board.json"
```

输出:
```
✅ Worktree 已创建
━━━━━━━━━━━━━━━━━━
任务: T-042 | 分支: task/T-042
目录: ../project--T-042
共享: task-board.json ✅ | events.db ✅
隔离: runtime/ ✅ | memory/ ✅ | docs/ ✅
下一步: cd ../project--T-042 && /agent implementer
```

### list — 列出活跃 Worktree

```bash
echo "📂 活跃 Worktree:"
echo "━━━━━━━━━━━━━━━━━━"
git worktree list --porcelain | while read -r line; do
  case "$line" in
    worktree\ *) dir="${line#worktree }";;
    branch\ *)
      branch="${line#branch refs/heads/}"
      task_id=""
      # 提取任务 ID
      if [[ "$branch" == task/* ]]; then
        task_id="${branch#task/}"
      fi
      if [ -n "$task_id" ]; then
        status=$(jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | .status // "unknown"' "$dir/.agents/task-board.json" 2>/dev/null || echo "?")
        printf "  %-20s %-15s %-15s %s\n" "$task_id" "$branch" "$status" "$dir"
      fi
      ;;
  esac
done
```

### status — Worktree 状态概览

```bash
echo "📊 Worktree 状态:"
git worktree list | while read -r dir commit branch; do
  branch="${branch//[\[\]]/}"
  if [[ "$branch" == task/* ]]; then
    task_id="${branch#task/}"
    # Git diff stat
    changed=$(cd "$dir" && git diff --stat HEAD | tail -1 || echo "clean")
    # Ahead/behind main
    ahead=$(cd "$dir" && git rev-list --count main..HEAD 2>/dev/null || echo "0")
    behind=$(cd "$dir" && git rev-list --count HEAD..main 2>/dev/null || echo "0")
    echo "  $task_id ($branch): $changed | ↑${ahead} ↓${behind} vs main"
  fi
done
```

### merge — 合并 & 清理

```bash
TASK_ID="$1"
PROJECT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
WORKTREE_DIR="${PROJECT_DIR}/../${PROJECT_NAME}--${TASK_ID}"
BRANCH_NAME="task/${TASK_ID}"

# 0. 确认任务状态
STATUS=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | .status' "$PROJECT_DIR/.agents/task-board.json")
if [ "$STATUS" != "accepted" ] && [ "$STATUS" != "testing" ] && [ "$STATUS" != "reviewing" ]; then
  echo "⚠️ 任务 $TASK_ID 状态为 $STATUS, 建议先完成审查/测试再合并"
  echo "继续合并? (y/N)"
  # 等待用户确认
fi

# 1. 回到主 worktree
cd "$PROJECT_DIR"

# 2. 复制 worktree 中的记忆和文档回主 worktree
if [ -d "$WORKTREE_DIR/.agents/memory" ]; then
  cp -r "$WORKTREE_DIR/.agents/memory/"* "$PROJECT_DIR/.agents/memory/" 2>/dev/null || true
fi
if [ -d "$WORKTREE_DIR/.agents/docs/$TASK_ID" ]; then
  mkdir -p "$PROJECT_DIR/.agents/docs/$TASK_ID"
  cp -r "$WORKTREE_DIR/.agents/docs/$TASK_ID/"* "$PROJECT_DIR/.agents/docs/$TASK_ID/" 2>/dev/null || true
fi

# 3. 合并分支
git merge "$BRANCH_NAME" --no-ff -m "Merge task/$TASK_ID: $(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id == $id) | .title' "$PROJECT_DIR/.agents/task-board.json")"

# 4. 清理 worktree
git worktree remove "$WORKTREE_DIR"
git branch -d "$BRANCH_NAME"

# 5. 更新 task-board — 移除 worktree 字段
jq --arg id "$TASK_ID" \
  '.tasks = [.tasks[] | if .id == $id then del(.worktree) else . end]' \
  "$PROJECT_DIR/.agents/task-board.json" > "$PROJECT_DIR/.agents/task-board.json.tmp" \
  && mv "$PROJECT_DIR/.agents/task-board.json.tmp" "$PROJECT_DIR/.agents/task-board.json"
```

输出:
```
✅ 合并完成
━━━━━━━━━━━━
任务: T-042 | 分支: task/T-042 → main
记忆: 已复制回主 worktree ✅
文档: 已复制回主 worktree ✅
Worktree: 已清理 ✅
```

## 使用场景

| 场景 | 命令 |
|------|------|
| 并行开发两个功能 | `create T-042` + `create T-043`, 各自独立开发 |
| 紧急修复插入 | `create T-FIX-001`, 不影响正在进行的任务 |
| 多人协作 | 每人负责一个 worktree, 通过共享看板协调 |
| A/B 方案对比 | 同一任务创建两个 worktree, 分别实现不同方案 |

## 约束

- 创建 worktree 前, 任务必须已存在于 task-board.json
- 合并前建议 rebase main: `cd ../project--T-042 && git rebase main`
- Worktree 目录命名规则: `<project-name>--<task-id>`
- 共享资源通过 symlink, 不要手动复制 task-board.json

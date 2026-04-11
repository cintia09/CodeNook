# 设计提案: Worktree-Based 并行任务开发

> 任务ID: T-WORKTREE | 状态: 设计中 | 优先级: HIGH

## 一、问题陈述

当前框架所有任务共享同一个工作目录。当需要同时开发多个任务时：
- 两个任务修改同一文件 → **文件冲突**
- Agent 无法区分哪些修改属于哪个任务 → **上下文混乱**
- 只能串行开发，完成一个才能开始下一个 → **吞吐量瓶颈**

## 二、方案: Git Worktree 隔离

### 核心思路

```
project/                              # 主 worktree (main 分支)
├── .agents/
│   ├── task-board.json               # ← 共享看板 (所有 worktree 可见)
│   ├── events.db                     # ← 共享审计日志
│   └── runtime/                      # ← 主 worktree 运行时
│
├── src/                              # 主分支代码

project--T-042/                       # worktree for T-042 (task/T-042 分支)
├── .agents/
│   ├── task-board.json → symlink     # 指向主 worktree
│   ├── events.db → symlink           # 指向主 worktree
│   └── runtime/                      # 独立运行时 (inbox, memory)
│
├── src/                              # T-042 独立修改

project--T-043/                       # worktree for T-043
├── ...                               # 同上
```

### 生命周期

```
1. 创建任务  →  git worktree add ../project--T-042 -b task/T-042
2. 开发阶段  →  在 worktree 中 /agent implementer → 独立编码
3. 审查阶段  →  同 worktree 中 /agent reviewer → 审查 diff
4. 完成合并  →  git checkout main && git merge task/T-042
5. 清理      →  git worktree remove ../project--T-042
```

## 三、共享 vs 隔离矩阵

| 资源 | 共享方式 | 原因 |
|------|---------|------|
| `task-board.json` | **Symlink** → 主 worktree | 全局看板，所有任务可见 |
| `events.db` | **Symlink** → 主 worktree | 统一审计日志 |
| `runtime/<agent>/inbox.json` | **隔离** (每个 worktree 独立) | 每个任务的消息队列独立 |
| `memory/T-NNN-*.json` | **隔离** (在各自 worktree 的 .agents/) | 任务记忆绑定任务 |
| `docs/T-NNN/` | **隔离** (在各自 worktree 的 .agents/) | 文档绑定任务 |
| Skills (全局) | **自动继承** (同一用户目录) | ~/.claude/skills/ 不在项目里 |
| Hooks (全局) | **自动继承** | ~/.claude/hooks/ 不在项目里 |
| 源代码 | **完全隔离** (独立分支) | 这是 worktree 的核心价值 |

## 四、需要新增/修改的组件

### 4a. `agent-worktree` skill (新增)

管理 worktree 生命周期的 skill：

```
/agent-worktree create T-042        # 创建 worktree + 分支 + symlinks
/agent-worktree list                # 列出所有活跃 worktree
/agent-worktree switch T-042        # cd 到对应 worktree
/agent-worktree merge T-042         # 合并回 main + 清理
/agent-worktree status              # 各 worktree 的 git diff stat
```

### 4b. `team-session.sh` 增强

```bash
# 现有: 同目录 tmux 分屏
bash scripts/team-session.sh --agents implementer,tester --task T-042

# 新增: worktree 模式 — 每个任务一个 tmux 窗口
bash scripts/team-session.sh --worktree --tasks T-042,T-043
```

每个 tmux 窗口 `cd` 到对应 worktree 目录，Agent 在隔离环境中工作。

### 4c. `auto-dispatch.sh` 修改

跨 worktree 消息路由：

```bash
# 当前: 写入 .agents/runtime/<agent>/inbox.json (同目录)
# 新增: 如果任务有 worktree，写入对应 worktree 的 inbox
WORKTREE_DIR=$(git worktree list --porcelain | grep "worktree.*T-${TASK_ID}" | head -1 | cut -d' ' -f2)
if [ -n "$WORKTREE_DIR" ]; then
  TARGET_INBOX="$WORKTREE_DIR/.agents/runtime/${TARGET_AGENT}/inbox.json"
fi
```

### 4d. task-board.json 扩展字段

```json
{
  "id": "T-042",
  "title": "用户认证",
  "status": "implementing",
  "worktree": {
    "path": "../project--T-042",
    "branch": "task/T-042",
    "created_at": "2025-01-15T10:00:00Z"
  }
}
```

## 五、并发安全

| 风险 | 场景 | 解决方案 |
|------|------|---------|
| task-board.json 竞写 | 两个 worktree 同时更新看板 | 已有 mkdir-based 原子锁 ✅ |
| events.db 竞写 | 两个任务同时写审计日志 | SQLite WAL 模式 + 框架现有锁 ✅ |
| Git 冲突 | 两个任务修改同一文件 | merge 时人工解决 (这是正常的 Git 流程) |
| 分支过期 | worktree 分支落后 main | merge 前 rebase: `git rebase main` |

## 六、Claude Code / Copilot CLI 适配

| 场景 | Claude Code | Copilot CLI |
|------|------------|-------------|
| 多窗口 | 每个终端 `cd` 到不同 worktree，各开一个 `claude` | 每个终端各开一个 `copilot` |
| 上下文 | 自动加载 worktree 目录下的 .agents/ | 同左 |
| Skills | 全局 ~/.claude/skills/ 自动继承 | 全局 ~/.copilot/skills/ 自动继承 |
| Hooks | 全局 hooks 自动生效 | 同左 |

> **关键优势**: Worktree 方案完全兼容现有平台，不需要任何 Claude Code/Copilot 的特殊支持。每个 worktree 就是一个普通的 Git 工作目录。

## 七、用户工作流示例

```bash
# 1. 创建两个并行任务
/agent acceptor
"创建任务 T-042: 用户认证系统"
"创建任务 T-043: 支付集成"

# 2. 为每个任务创建 worktree
/agent-worktree create T-042
/agent-worktree create T-043

# 3. 在终端 1 开发 T-042
cd ../project--T-042
/agent implementer
"实现 T-042 的登录功能"

# 4. 同时在终端 2 开发 T-043
cd ../project--T-043
/agent implementer
"实现 T-043 的支付接口"

# 5. 两个任务独立推进，互不干扰

# 6. T-042 完成后合并
/agent-worktree merge T-042
# → git merge task/T-042 into main
# → 清理 worktree

# 7. T-043 rebase 最新 main 继续开发
cd ../project--T-043 && git rebase main
```

## 八、实施计划

| 阶段 | 内容 | 改动量 |
|------|------|--------|
| P1 | `agent-worktree` skill (create/list/merge/status) | 新增 ~200 行 |
| P2 | `team-session.sh` --worktree 模式 | 修改 ~50 行 |
| P3 | `auto-dispatch.sh` 跨 worktree 路由 | 修改 ~20 行 |
| P4 | task-board.json worktree 字段 + FSM 感知 | 修改 ~30 行 |
| P5 | 文档 + 测试 | 新增 ~100 行 |

总计: ~400 行新增/修改

## 九、不做什么

- ❌ 不自动 rebase/merge — 冲突解决由人决定
- ❌ 不修改 Git 行为 — 纯粹利用 `git worktree` 原生功能
- ❌ 不强制 worktree — 简单任务继续在主目录开发
- ❌ 不跨机器同步 — worktree 是本地概念

---

> 📝 设计者: Copilot | 审阅状态: 待审阅

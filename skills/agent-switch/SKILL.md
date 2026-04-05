---
name: agent-switch
description: "Agent 状态面板: 查看所有 Agent 的状态、任务分配和消息队列。Use when checking agent status or task overview."
---

# Agent 角色管理

## 查看所有 Agent 状态 (/agent status)
读取项目下每个 Agent 的 state.json, 汇总显示:

```
🤖 Agent 状态面板
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
角色       状态     当前任务    队列        最后活动
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 验收者   idle     —          —          10:00
🏗️ 设计者   busy     T-002      —          10:30
💻 实现者   idle     —          [T-003]    09:45
🔍 审查者   idle     —          —          09:00
🧪 测试者   busy     T-001      —          10:15
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

�� 任务表摘要: 3 个任务 (1 完成, 1 进行中, 1 待处理)
```

### 实现步骤:
```bash
AGENTS_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.agents"
[ -d "$AGENTS_DIR" ] || AGENTS_DIR="./.agents"

for agent in acceptor designer implementer reviewer tester; do
  cat "$AGENTS_DIR/runtime/$agent/state.json"
done

cat "$AGENTS_DIR/task-board.json"
```

## 切换角色 (/agent <name>)
用户说 "/agent <name>" 或 "切换到 <角色名>" 时:
1. 确认目标角色有效: acceptor | designer | implementer | reviewer | tester
2. 保存当前 Agent 状态 (如果有)
3. **写入 active-agent 标记** (供 Hooks 读取):
   ```bash
   echo "<agent_name>" > <project>/.agents/runtime/active-agent
   ```
4. 清洁上下文 (RESPAWN 模式 — 不携带上一个 Agent 的工作记忆)
5. 加载目标 Agent 的 skill (agent-<name>.md)
6. 执行目标 Agent 的启动流程 (定义在对应 skill 中)
7. 打印: "🔄 已切换到 <角色名> (<emoji>)"

### 退出角色
用户说 "退出角色" 或 "exit agent" 时:
```bash
rm -f <project>/.agents/runtime/active-agent
```

## 可用角色
| 命令 | 角色 | Emoji |
|------|------|-------|
| `/agent acceptor` | 验收者 | 🎯 |
| `/agent designer` | 设计者 | 🏗️ |
| `/agent implementer` | 实现者 | 💻 |
| `/agent reviewer` | 审查者 | 🔍 |
| `/agent tester` | 测试者 | 🧪 |
| `/agent status` | 状态面板 | 🤖 |

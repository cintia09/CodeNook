---
name: project-tester
description: "本项目的测试框架和测试策略。测试者 agent 工作时加载。"
---

# 项目级测试指南

## 测试框架
- **自动化**: N/A (纯 Markdown 框架)
- **集成测试**: 手动 — Copilot CLI 新会话验证
- **格式验证**: bash 脚本检查文件结构

## 测试命令
| 操作 | 命令 |
|------|------|
| 检查 skills | `ls -d ~/.copilot/skills/agent-* \| wc -l` (expect: 10) |
| 检查 agents | `ls ~/.copilot/agents/*.agent.md \| wc -l` (expect: 5) |
| 检查 hooks | `ls ~/.copilot/hooks/agent-*.sh \| wc -l` (expect: 3) |
| 验证 SKILL.md | `ls ~/.copilot/skills/agent-*/SKILL.md \| wc -l` (expect: 10) |
| 路径一致性 | `grep -rn '\.copilot/' skills/ agents/ \| grep -v '~/\.copilot'` (应无输出) |
| Hook 测试 | 用 echo + pipe 模拟 JSON 输入 |
| 查询审计日志 | `sqlite3 .agents/events.db "SELECT count(*) FROM events;"` |

## 测试策略
### 安装测试 (每次发布前)
1. 清除 → 从 GitHub 安装 → 验证数量和格式

### 初始化测试
1. 删除 `.agents/` → "初始化 Agent 系统" → 验证目录结构

### Hook 测试
1. 设置 active-agent → 模拟 preToolUse 输入 → 验证 deny/allow
2. 模拟 postToolUse → 验证 events.db 有记录

### Skill 触发测试
| Skill | 触发语 | 预期行为 |
|-------|--------|---------|
| agent-init | "初始化 Agent 系统" | 创建 .agents/ |
| agent-fsm | "更新任务状态" | 读取/修改 state.json |
| agent-task-board | "创建任务" | 写入 task-board.json |
| agent-messaging | "发消息给测试者" | 写入 inbox.json |
| agent-switch | "查看 Agent 状态" | 显示状态面板 |

## 测试环境
- macOS + Copilot CLI
- 需要 `jq` 和 `sqlite3` (macOS 自带)

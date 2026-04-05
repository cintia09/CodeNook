---
name: project-tester
description: "本项目的测试框架和测试策略。测试者 agent 工作时加载。"
---

# 项目级测试指南

## 测试框架
- **自动化测试**: N/A (纯 Markdown 框架, 无可执行代码)
- **集成测试**: 手动 — 在 Copilot CLI 新会话中验证功能
- **格式验证**: bash 脚本检查文件结构和 YAML frontmatter

## 测试命令
| 操作 | 命令 |
|------|------|
| 检查 skill 数量 | `ls -d ~/.copilot/skills/agent-* \| wc -l` (expect: 10) |
| 检查 agent 数量 | `ls ~/.copilot/agents/*.agent.md \| wc -l` (expect: 5) |
| 验证 SKILL.md 存在 | `for d in ~/.copilot/skills/agent-*/; do [ -f "$d/SKILL.md" ] && echo "✅ $(basename $d)" \|\| echo "❌ $(basename $d)"; done` |
| 验证 YAML frontmatter | `head -3 ~/.copilot/skills/agent-*/SKILL.md` |
| 检查路径一致性 | `grep -rn '\.copilot/' skills/ agents/ \| grep -v '~/\.copilot'` (应无输出) |

## 测试策略

### 安装测试 (每次发布前)
1. 清除: `rm -rf ~/.copilot/skills/agent-* ~/.copilot/agents/*.agent.md`
2. 按 AGENTS.md 从 GitHub 安装
3. 验证文件数量和格式
4. 新会话: `/agent` 显示 5 角色

### 初始化测试
1. 在临时目录创建空项目: `mkdir /tmp/test-init && cd /tmp/test-init && git init`
2. 说 "初始化 Agent 系统"
3. 验证 `.agents/` 目录结构正确
4. 验证 state.json 初始值正确
5. 清理: `rm -rf /tmp/test-init`

### Skill 触发测试
| Skill | 触发语 | 预期行为 |
|-------|--------|---------|
| agent-init | "初始化 Agent 系统" | 创建 .agents/ 目录 |
| agent-fsm | "更新任务状态" | 读取/修改 state.json |
| agent-task-board | "创建任务" | 写入 task-board.json |
| agent-messaging | "发消息给测试者" | 写入 inbox.json |
| agent-switch | "查看 Agent 状态" | 显示状态面板 |

### 回归测试
- Bug 修复: 先确认 bug 可复现 → 修复后确认不再出现
- 测试用例输出到: `.agents/runtime/tester/workspace/test-cases/`
- 问题报告输出到: `.agents/runtime/tester/workspace/issues-report.md`

## 测试环境
- macOS + Copilot CLI (当前版本)
- 需要 SSH 访问 GitHub (git@github.com)
- 需要 `~/.copilot/` 目录写入权限

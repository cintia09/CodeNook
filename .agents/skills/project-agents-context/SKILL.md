---
name: project-agents-context
description: "项目上下文信息, 所有 agent 工作时自动获取。包含技术栈、构建命令、部署方式等。"
---

# 项目上下文

## 项目信息
- **名称**: multi-agent-framework
- **描述**: 零依赖、基于文件的多 Agent 协作框架, 适配 GitHub Copilot CLI 和 Claude Code
- **仓库**: cintia09/multi-agent-framework (branch: main)

## 技术栈
- **语言**: Markdown (agent profiles, skills), JSON (state files, task board)
- **框架**: GitHub Copilot CLI native agent/skill system
- **数据库**: N/A (file-based persistence)
- **测试**: Manual testing via Copilot CLI (no automated test suite)
- **CI**: N/A
- **部署**: `cp` commands to `~/.copilot/skills/` and `~/.copilot/agents/`

## 常用命令
| 操作 | 命令 |
|------|------|
| 安装到本地 | `cp -r skills/agent-* ~/.copilot/skills/ && cp agents/*.agent.md ~/.copilot/agents/` |
| 验证安装 | `ls -d ~/.copilot/skills/agent-* \| wc -l` (expect 10) |
| 验证 agents | `ls ~/.copilot/agents/*.agent.md \| wc -l` (expect 5) |
| 测试 skill | 新会话中说 "初始化 Agent 系统" 或 `/agent` |
| Git push | `git push origin main` |

## 目录结构
- `agents/` — 5 个 `.agent.md` 角色配置文件 (验收/设计/实现/审查/测试)
- `skills/` — 10 个 `agent-*/SKILL.md` 技能文件 (FSM/任务表/消息/初始化/5角色)
- `docs/` — 协作规则 (`agent-rules.md`)
- `.agents/` — 项目初始化后的运行时目录 (state, tasks, runtime)
- `AGENTS.md` — 安装指引 (Copilot 自动读取)
- `README.md` — 完整文档

## 分支策略
- `main` — 唯一分支, 直接 push
- 提交消息: 英文, 含 `Co-authored-by: Copilot` trailer

## 项目特殊性
这是一个 **元项目** — 它本身就是 Agent 协作框架。修改 `skills/` 或 `agents/` 下的文件后, 需要同步到 `~/.copilot/` 全局目录才能在其他项目生效。

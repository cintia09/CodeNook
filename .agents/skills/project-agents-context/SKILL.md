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
- **语言**: Markdown (agent profiles, skills), JSON (state files, task board), Bash (hooks)
- **框架**: GitHub Copilot CLI native agent/skill/hook system
- **数据库**: SQLite (events.db audit log)
- **测试**: Manual testing via Copilot CLI (no automated test suite)
- **CI**: N/A
- **部署**: `cp` commands to `~/.copilot/{skills,agents,hooks}/`

## 常用命令
| 操作 | 命令 |
|------|------|
| 安装到本地 | 按 AGENTS.md 步骤: clone → cp skills → cp agents → cp hooks |
| 验证安装 | `ls -d ~/.copilot/skills/agent-* \| wc -l` (expect 10) |
| 验证 agents | `ls ~/.copilot/agents/*.agent.md \| wc -l` (expect 5) |
| 验证 hooks | `ls ~/.copilot/hooks/agent-*.sh \| wc -l` (expect 3) |
| 查询审计日志 | `sqlite3 .agents/events.db "SELECT * FROM events ORDER BY id DESC LIMIT 20;"` |
| Git push | `git push origin main` |

## 目录结构
- `agents/` — 5 个 `.agent.md` 角色配置文件
- `skills/` — 10 个 `agent-*/SKILL.md` 技能文件
- `hooks/` — 3 个 hook 脚本 + hooks.json 配置
- `docs/` — 协作规则 (`agent-rules.md`)
- `.agents/` — 项目初始化后的运行时目录
- `AGENTS.md` — 安装指引
- `README.md` — 完整文档

## 分支策略
- `main` — 唯一分支, 直接 push
- 提交消息: 英文, 含 `Co-authored-by: Copilot` trailer

## 项目特殊性
这是一个 **元项目** — 修改 `skills/`, `agents/`, `hooks/` 后需同步到 `~/.copilot/` 全局目录。

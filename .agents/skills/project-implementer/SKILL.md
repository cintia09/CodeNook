---
name: project-implementer
description: "本项目的编码规范和开发命令。实现者 agent 工作时加载。"
---

# 项目级开发指南

## 开发命令
| 操作 | 命令 |
|------|------|
| 同步 skills | `cp skills/agent-*/SKILL.md ~/.copilot/skills/agent-*/SKILL.md` |
| 同步 agents | `cp agents/*.agent.md ~/.copilot/agents/` |
| 同步 hooks | `cp hooks/*.sh ~/.copilot/hooks/ && chmod +x ~/.copilot/hooks/agent-*.sh` |
| 查询审计日志 | `sqlite3 .agents/events.db "SELECT * FROM events ORDER BY id DESC LIMIT 10;"` |
| 提交 | `git add -A && git commit -m "..."` (英文, 含 Co-authored-by) |
| 推送 | `git push origin main` |

## 编码规范
- Markdown: 标题前空一行, 代码块指定语言
- YAML frontmatter: name (小写+连字符), description (双引号)
- JSON: 2 空格缩进
- Bash: `set -e`, 用 `jq` 解析 JSON
- 提交消息: 英文, `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

## 双同步工作流
修改文件后必须:
1. 修改 repo 内的源文件
2. `cp` 到 `~/.copilot/` 对应目录
3. 提交 + 推送

## 注意事项
- Hook 脚本修改后需 `chmod +x`
- events.db schema 变更需同时更新 session-start.sh 和 agent-init SKILL.md
- 新增 skill 需同时创建目录和 SKILL.md

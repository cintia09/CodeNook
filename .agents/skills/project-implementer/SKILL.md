---
name: project-implementer
description: "本项目的编码规范和开发命令。实现者 agent 工作时加载。"
---

# 项目级开发指南

## 开发命令
| 操作 | 命令 | 说明 |
|------|------|------|
| 同步到全局 | `cp skills/agent-*/SKILL.md ~/.copilot/skills/agent-*/SKILL.md` | 修改 skill 后 |
| 同步 agents | `cp agents/*.agent.md ~/.copilot/agents/` | 修改 agent 后 |
| 验证 skills | `for d in ~/.copilot/skills/agent-*/; do ls "$d/SKILL.md"; done` | 确认文件存在 |
| 验证 agents | `ls ~/.copilot/agents/*.agent.md` | 确认文件存在 |
| 提交 | `git add -A && git commit -m "..."` | 含 Co-authored-by |
| 推送 | `git push origin main` | main 分支直推 |

## 编码规范
- **Markdown**: 标题前空一行, 代码块指定语言, 表格对齐
- **YAML frontmatter**: name (小写+连字符), description (双引号包裹)
- **JSON**: 2 空格缩进, 格式化输出
- **提交消息**: 英文, 首行 ≤ 72 字符, 含 `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`

## 文件管理
- **仓库文件**: `agents/`, `skills/`, `docs/`, `AGENTS.md`, `README.md`
- **运行时文件**: `.agents/runtime/` (gitignored)
- **项目 skills**: `.agents/skills/project-*` (可提交)

## TDD 工作流 (项目适配)
由于项目无自动化测试, TDD 通过手动验证:
1. 修改 skill/agent 文件
2. 同步到 `~/.copilot/` 全局目录
3. 新 Copilot CLI 会话中测试: `/agent` 或触发对应 skill
4. 验证行为是否符合预期
5. 确认后提交 + push

## 注意事项
- 修改 skill 后必须同时同步 repo 和 `~/.copilot/` 两处
- 每个 skill 的 SKILL.md 是唯一文件名, 不可改名
- `.agents/` 下的 `runtime/` 目录不提交到 git

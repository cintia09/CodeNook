---
name: project-reviewer
description: "本项目的审查标准和代码质量要求。审查者 agent 工作时加载。"
---

# 项目级审查指南

## 审查清单
- [ ] YAML frontmatter 格式正确 (name, description)
- [ ] Skill name 遵循命名规范 (agent-* 或 project-*)
- [ ] Description 包含触发条件
- [ ] 文件路径一致: 项目用 `.agents/`, 全局用 `~/.copilot/`
- [ ] JSON 有 version 字段 (乐观锁)
- [ ] Hook 脚本有 `set -e` 和正确的 shebang
- [ ] Hook 输出有效 JSON (preToolUse)
- [ ] 新文件已同步到 repo 和 `~/.copilot/`
- [ ] 提交消息英文 + Co-authored-by

## 项目特有规则
- Agent profile ≤ 30,000 字符
- Skill 自包含, 不依赖其他 skill 内部实现
- FSM 状态名与 agent profiles 中引用一致
- Hook 超时 ≤ 30 秒 (默认), 性能敏感

## 审查报告
输出到 `.agents/runtime/reviewer/workspace/review-reports/review-T-NNN-YYYY-MM-DD.md`:
- 🔴 必须修复
- 🟡 建议修复
- ✅ 总评: pass / fail

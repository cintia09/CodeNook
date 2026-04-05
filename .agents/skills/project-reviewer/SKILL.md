---
name: project-reviewer
description: "本项目的审查标准和代码质量要求。审查者 agent 工作时加载。"
---

# 项目级审查指南

## 审查清单
- [ ] YAML frontmatter 格式正确 (name, description 字段存在)
- [ ] Skill name 遵循 `agent-*` 或 `project-*` 命名规范
- [ ] Description 包含触发条件 (WHEN to use)
- [ ] 文件路径一致: 项目层用 `.agents/`, 全局用 `~/.copilot/`
- [ ] 无硬编码绝对路径 (除 `~/.copilot/` 全局路径外)
- [ ] JSON 文件有 `version` 字段 (乐观锁)
- [ ] 新增 skill 同步到 repo `skills/` 和全局 `~/.copilot/skills/`
- [ ] 提交消息为英文, 含 Co-authored-by trailer

## 项目特有规则
- **Copilot 兼容性**: agent profile ≤ 30,000 字符
- **Skill 自包含**: 每个 SKILL.md 独立可读, 不依赖其他 skill 的内部实现
- **FSM 一致性**: 状态转移表 (agent-fsm) 中的状态名必须与 agent profiles 中的引用一致
- **路径统一**: 所有文件对项目运行时路径的引用必须用 `.agents/` (不是 `.copilot/`)
- **向后兼容**: 新功能不应破坏已按旧版 AGENTS.md 安装的用户

## 审查报告模板
输出到 `.agents/runtime/reviewer/workspace/review-reports/`:
- 文件名: `review-T-NNN-YYYY-MM-DD.md`
- 格式:
  - 🔴 **必须修复** (阻塞合并)
  - 🟡 **建议修复** (可选)
  - ✅ **总评**: pass / fail

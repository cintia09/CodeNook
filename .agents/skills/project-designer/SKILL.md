---
name: project-designer
description: "本项目的架构约束和技术选型。设计者 agent 工作时加载。"
---

# 项目级设计指南

## 现有架构
- **类型**: 纯文件型框架 (Markdown + JSON + Bash)
- **层级**: 全局 (`~/.copilot/`) → 项目 (`.agents/`)
- **组件**: agents (5 角色) + skills (10 全局 + 6 项目) + hooks (3 脚本)
- **通信**: inbox.json 消息队列 + active-agent 文件 + events.db 审计

## 技术约束
- Agent profile ≤ 30,000 字符
- Skill: `{name}/SKILL.md` 目录结构, YAML frontmatter 必须有 name + description
- Hook: hooks.json 配置 + 可执行 .sh 脚本, 默认 30 秒超时
- 路径约定: 全局 `~/.copilot/`, 项目 `.agents/`

## 设计文档模板
输出到 `.agents/runtime/designer/workspace/design-docs/`:
1. 需求摘要 (引用 goal ID)
2. 影响分析 (哪些文件需要修改)
3. 兼容性说明 (是否需要重新安装)
4. 测试规格 → `test-specs/`

## 设计原则
- 渐进增强: 不破坏旧版安装
- 自包含: 每个文件独立可读
- Hook 优先: 强制行为用 hook, 不靠 LLM 自律

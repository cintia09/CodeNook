---
name: project-designer
description: "本项目的架构约束和技术选型。设计者 agent 工作时加载。"
---

# 项目级设计指南

## 现有架构
- **类型**: 纯文件型框架 (零代码依赖)
- **入口**: AGENTS.md (安装) → agent-init SKILL.md (初始化) → 各角色 agent.md (运行时)
- **状态管理**: JSON 文件 + 乐观锁 (version 字段)
- **通信方式**: inbox.json 消息队列 (异步, 文件级)

## 技术约束
- **Copilot CLI 限制**: 每个 agent profile ≤ 30,000 字符
- **Skill 格式**: 必须是 `{name}/SKILL.md` 目录结构, YAML frontmatter 必须有 name + description
- **Agent 格式**: `.agent.md` 文件, YAML frontmatter 至少有 description
- **路径约定**: 全局用 `~/.copilot/`, 项目用 `.agents/`
- **无代码执行**: 框架本身不运行代码, 只是指令集 — AI 解释执行

## 设计文档模板
设计文档输出到 `.agents/runtime/designer/workspace/design-docs/`, 包含:
1. 需求摘要 (引用 goal ID)
2. 影响分析 (哪些 skill/agent 文件需要修改)
3. Markdown 结构设计 (新增的章节/字段)
4. 兼容性说明 (是否需要重新安装, 是否向后兼容)
5. 测试规格 → `test-specs/` (如何验证变更)

## 设计原则
- **渐进增强**: 新功能不破坏已安装的旧版本
- **自包含**: 每个 skill 文件独立可读, 不依赖隐式知识
- **Copilot 友好**: description 字段是 AI 发现的关键, 必须精确
- **人类可读**: JSON 状态文件保持格式化, Markdown 表格保持对齐

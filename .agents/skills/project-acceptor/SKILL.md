---
name: project-acceptor
description: "本项目的验收标准和业务背景。验收者 agent 工作时加载。"
---

# 项目级验收指南

## 业务背景
multi-agent-framework 为 AI 编码助手提供多角色协作框架。目标用户: 使用 Copilot CLI 或 Claude Code 的开发者。

## 验收标准基线
- **安装测试**: 按 AGENTS.md 步骤安装, 验证 10 skills + 5 agents + 3 hooks
- **格式检查**: 所有 `.agent.md` 有 YAML frontmatter, 所有 `SKILL.md` 有 name + description
- **功能测试**: `/agent` 显示 5 角色; "初始化 Agent 系统" 创建 `.agents/`; hooks 正确执行
- **Hook 测试**: pre-tool-use 能拦截越权操作; post-tool-use 写入 events.db

## 验收流程
1. 清除已有安装
2. 从 GitHub 克隆并按 AGENTS.md 安装
3. 验证文件数量: 10 skills, 5 agents, 3 hooks, hooks.json
4. 新会话: `/agent` 确认 5 角色可见
5. 新会话: "初始化 Agent 系统" 确认 `.agents/` 目录正确生成
6. 验证 events.db 有审计记录

## 质量红线
- 安装必须使用 `cp`, 绝不用 heredoc
- Skill description 必须包含触发条件
- 所有文件路径使用 `.agents/` (项目层)
- Hook 脚本必须有执行权限

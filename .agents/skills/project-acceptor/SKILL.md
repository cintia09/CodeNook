---
name: project-acceptor
description: "本项目的验收标准和业务背景。验收者 agent 工作时加载。"
---

# 项目级验收指南

## 业务背景
multi-agent-framework 是一个为 AI 编码助手设计的多角色协作框架。目标用户是使用 GitHub Copilot CLI 或 Claude Code 的开发者, 希望通过 5 个专业角色分工协作来提升软件开发质量。

## 验收标准基线
- **安装测试**: 按 AGENTS.md 步骤安装, 验证 10 skills + 5 agents 正确复制
- **格式检查**: 所有 `.agent.md` 有 YAML frontmatter, 所有 `SKILL.md` 有 name + description
- **功能测试**: 新会话中 `/agent` 显示 5 个角色; "初始化 Agent 系统" 触发 init skill
- **Lint 检查**: N/A (纯 Markdown 项目)
- **覆盖率要求**: N/A

## 验收流程
1. 清除已有安装: `rm -rf ~/.copilot/skills/agent-* ~/.copilot/agents/*.agent.md`
2. 从 GitHub 克隆并按 AGENTS.md 安装
3. 验证文件数量: 10 skill dirs, 5 agent files
4. 新会话: `/agent` → 确认 5 角色可见
5. 新会话: "初始化 Agent 系统" → 确认 `.agents/` 目录正确生成
6. 检查生成的 project skills 内容是否合理 (非空, 有项目特定信息)

## 质量红线
- 安装必须使用 `cp`, 绝不用 heredoc 重建文件
- Skill description 必须包含触发条件 (WHEN to use)
- Agent 间不能有循环依赖 (FSM 必须是 DAG)
- 所有文件路径使用 `.agents/` 而非 `.copilot/` (项目层)

# T-SKILL-OPT: Skills 机制优化 — 需求文档

> **角色**: Acceptor  
> **任务 ID**: T-SKILL-OPT  
> **优先级**: Medium  
> **版本**: v3.0  
> **基于**: `skills-mechanism-report.md` 深度分析报告  
> **适配平台**: Claude Code / GitHub Copilot CLI

---

## 一、背景

基于 Claude Code 源码分析 + Copilot CLI 官方文档 + 本机配置验证，发现以下关键事实：

1. **两平台共享 Agent Skills 开源标准**（`agentskills.io`）— 同一 `SKILL.md` 格式
2. **注入机制一致**：摘要列表（~1% token）+ 按需全文加载（非之前理解的"全量注入 40%"）
3. **Per-Agent Skill 隔离**：当前框架所有 agent 看到相同的 18 个 skills，缺乏角色级隔离
4. **文档不准确**：`docs/llm-message-structure.md` 中 token 分布描述与实际机制不符

### 两平台 Skill 机制对比

| 维度 | Claude Code | GitHub Copilot CLI |
|------|------------|-------------------|
| **发现路径** | `~/.claude/skills/` + `.claude/skills/` + `.agents/skills/` | `~/.copilot/skills/` + `.github/skills/` + `.claude/skills/` + `.agents/skills/` |
| **共享路径** | `.claude/skills/` ✅ `.agents/skills/` ✅ | `.claude/skills/` ✅ `.agents/skills/` ✅ |
| **注入策略** | 摘要列表 ~1% + 按需全文 | 摘要列表 + 按需调用 |
| **选择性加载** | frontmatter `disable-model-invocation` / `paths:` | `/skills` 命令启用/禁用 |
| **Per-Agent 隔离** | prompt 软约束 | prompt 软约束 |
| **热加载** | ⚠️ memoize 缓存，需新会话 | `/skills reload` |

---

## 二、需求清单

### R1: 修正 Token 分布文档

**优先级**: HIGH  
**类型**: 文档修正

`docs/llm-message-structure.md` 中 token 分布图将 Skills 标为 ~40%，实际应为：
- **~1%**: Skill 摘要列表（每轮注入 system prompt）
- **~5-15%**: 被调用的 skill 全文（出现在 messages 数组中，按需加载）
- Custom Instructions (`copilot-instructions.md` / `CLAUDE.md`) ≠ Skills

**验收标准**:
- [ ] Token 分布图（Mermaid pie chart）数值准确反映两级加载机制
- [ ] ASCII 包结构图中 Skills 部分标注"摘要列表 ~1%"而非"全文"
- [ ] 新增说明段落解释"摘要发现 + 按需加载"机制

### R2: 实现 Per-Agent Skill 软约束

**优先级**: HIGH  
**类型**: 功能增强

在 5 个 `.agent.md` 文件中添加 `skills:` 声明和 prompt 约束，实现角色级 skill 隔离。

**Skill 分配矩阵**:

| Skill | acceptor | designer | implementer | reviewer | tester | 说明 |
|-------|:--------:|:--------:|:-----------:|:--------:|:------:|------|
| agent-orchestrator | ✅ | ✅ | ✅ | ✅ | ✅ | 全局调度 |
| agent-fsm | ✅ | ✅ | ✅ | ✅ | ✅ | 状态机 |
| agent-task-board | ✅ | ✅ | ✅ | ✅ | ✅ | 任务看板 |
| agent-messaging | ✅ | ✅ | ✅ | ✅ | ✅ | 消息收发 |
| agent-memory | ✅ | ✅ | ✅ | ✅ | ✅ | 记忆管理 |
| agent-switch | ✅ | ✅ | ✅ | ✅ | ✅ | 角色切换 |
| agent-docs | ✅ | ✅ | ✅ | ✅ | ✅ | 文档流水线 |
| agent-config | ✅ | — | — | — | — | 项目配置 |
| agent-init | ✅ | — | — | — | — | 项目初始化 |
| agent-acceptor | ✅ | — | — | — | — | 验收规范 |
| agent-designer | — | ✅ | — | — | — | 设计规范 |
| agent-implementer | — | — | ✅ | — | — | 实现规范 |
| agent-reviewer | — | — | — | ✅ | — | 审查规范 |
| agent-tester | — | — | — | — | ✅ | 测试规范 |
| agent-events | — | — | ✅ | — | ✅ | 事件日志 |
| agent-hooks | — | — | ✅ | — | — | Hook 开发 |
| agent-hypothesis | — | ✅ | ✅ | — | — | 假设探索 |
| agent-teams | ✅ | — | — | — | — | 团队编排 |

**验收标准**:
- [ ] 5 个 `.agent.md` 文件均有 `skills:` 列表声明
- [ ] Prompt 中有明确的"只能调用以下 skills"约束语句
- [ ] Prompt 中有"严禁调用其他角色 skills"的负约束
- [ ] 分配矩阵与上表一致（共享 7 + 角色专属）

### R3: 更新 Skills 机制架构文档

**优先级**: MEDIUM  
**类型**: 文档更新

`docs/skills-mechanism.md` 需要更新，反映最新发现。

**验收标准**:
- [ ] 新增"两级加载"流程图（Mermaid sequence diagram）
- [ ] 新增两平台 skill 发现路径对比图
- [ ] 更新 Per-Agent 隔离说明（从"全量注入"改为"摘要 + 按需"）
- [ ] 记录各平台热加载差异和 memoize 缓存注意事项

### R4: 支持两种安装方式

**优先级**: MEDIUM  
**类型**: 文档 + 功能增强

#### R4-A: 一键安装（脚本自动）

```bash
curl -sL https://raw.githubusercontent.com/cintia09/multi-agent-framework/main/install.sh | bash
```

已有功能，保持现状。脚本自动检测平台、下载、安装全部组件。

#### R4-B: 提示安装（AI 引导）

用户对 AI 助手说：
> "根据 cintia09/multi-agent-framework 仓库里的指引，将 agents 安装到我本地。"

AI 助手读取 README 后，按照文档指引自行完成安装。

**需要确保 README 中有足够清晰的安装指引**，包括：
1. 目标目录结构（`~/.claude/` 和 `~/.copilot/`）
2. 需要复制的文件列表（18 skills, 5 agents, 13 hooks, hooks.json, rules）
3. 文件对应关系（如 `hooks.json` vs `hooks-copilot.json`）
4. 权限设置（`chmod +x` hook 脚本）
5. 验证命令（如何确认安装成功）

**验收标准**:
- [ ] README 中"一键安装"部分保持 `curl | bash` 方式
- [ ] README 中新增"提示安装"部分，写明对 AI 说的提示语
- [ ] README 中有完整的手动安装步骤（目录结构 + 文件列表 + 权限），AI 可以直接跟随执行
- [ ] 手动安装步骤的信息与 `install.sh` 逻辑一致
- [ ] 包含安装后验证方法（`install.sh --check`）

### R5: 添加 `paths:` 条件激活（可选优化）

**优先级**: LOW  
**类型**: 功能增强（可选）

为适用的 skills 添加 `paths:` frontmatter 条件：

| Skill | paths 条件 |
|-------|-----------|
| agent-tester | `tests/**`, `**/*.test.*`, `**/*.spec.*` |
| agent-hooks | `hooks/**`, `**/*.sh` |
| agent-implementer | `src/**`, `lib/**`, `**/*.ts`, `**/*.py` |

**验收标准**:
- [ ] 添加 `paths:` 的 skills 仅在匹配文件时出现在摘要列表
- [ ] 不影响手动 `/skillname` 调用
- [ ] 不影响 Copilot CLI 兼容性

---

## 三、优先级排序

```
R2 (HIGH)  → Per-Agent skill 隔离（安全特性）
R1 (HIGH)  → 修正 token 文档（消除错误认知）
R4 (MEDIUM)→ 双模式安装（一键 + 交互）
R3 (MEDIUM)→ 架构文档更新（知识沉淀）
R5 (LOW)   → paths: 条件激活（锦上添花）
```

**建议实施顺序**: R2 → R1 → R4 → R3 → R5

---

## 四、约束与假设

1. **不修改 platform 代码** — 所有优化在框架层面完成（`.agent.md`、`SKILL.md`、文档、`install.sh`）
2. **向后兼容** — `install.sh` 无参数时保持当前行为
3. **Agent Skills 开源标准** — 所有变更符合 `agentskills.io` 规范
4. **双平台** — 所有变更同时适用 Claude Code 和 Copilot CLI
5. **提示安装依赖** — README 文档需足够清晰，AI 助手（Claude Code/Copilot CLI）可直接跟随执行
6. **隔离范围** — Per-Agent Skill 隔离**仅影响项目级别**的 5 个 agent 角色之间（designer/implementer/tester/reviewer/acceptor）。不影响非 agent 模式下的正常 skill 使用，不影响全局 baoyu-* 等其他 skills，不影响其他项目

---

## 五、非功能需求

- **Token 效率**: Per-Agent 隔离后，每个 agent 摘要列表从 18 降至 ~10-12 skills
- **可审计性**: `.agent.md` 中的 skill 约束清单可直接用于审计
- **安装体验**: 提示安装方式的 README 指引需清晰到 AI 助手可直接执行
- **文档准确性**: 所有文档图表必须与实际实现一致

# T-009: 按下游 Agent 角色智能加载记忆

## Context

当前 `agent-switch` 切换 Agent 时，会加载完整的 `T-NNN-memory.json` 记忆文件。问题是：
1. 不同角色需要的信息不同——Implementer 关心设计决策和文件结构，Reviewer 关心修改了哪些文件和决策理由
2. 加载完整 JSON 浪费 token，且噪声信息降低 Agent 效率
3. 原始 JSON 格式不够人类可读，Agent 解析困难

## Decision

在 `agent-switch` 切换逻辑中增加**角色感知的记忆过滤和格式化**：根据目标 Agent 角色，只提取相关字段，并格式化为简洁的 Markdown 摘要注入 Agent 上下文。

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: 角色字段映射 + Markdown 格式化（选中）** | 精准、token 效率高、可读性好 | 需要维护角色-字段映射表 | ✅ 选中 |
| **B: 全量加载 + 让 Agent 自行过滤** | 实现简单 | 浪费 token，Agent 可能忽略重要信息 | ❌ 低效 |
| **C: 每个角色一份独立记忆文件** | 加载简单 | 写入时需要维护多份文件，数据不一致风险 | ❌ 维护负担 |
| **D: LLM 动态摘要** | 摘要质量最高 | 额外 LLM 调用成本，延迟增加 | ❌ 成本过高 |

## Design

### Architecture

```
┌────────────────────────────┐
│  用户: /agent implementer  │
└─────────────┬──────────────┘
              ▼
┌─────────────────────────────────────────────┐
│  agent-switch SKILL.md 逻辑                   │
│  ├── 1. 切换 active-agent                     │
│  ├── 2. 检查 inbox                            │
│  ├── 3. 查找当前任务 (task-board.json)          │
│  └── 4. 【新增】智能记忆加载                     │
│       ├── 读取 .agents/memory/T-NNN-memory.json│
│       ├── 按角色映射表过滤字段                    │
│       └── 格式化为 Markdown 摘要输出             │
└─────────────────────────────────────────────┘
```

### Data Model

**角色-字段映射表**：

| 转换路径 | 加载字段 | 理由 |
|---------|---------|------|
| Designer → Implementer | `decisions`, `artifacts`, `handoff_notes`, `summary` | 实现者需要知道设计决策和产出物 |
| Implementer → Reviewer | `files_modified`, `decisions`, `summary`, `issues_encountered` | 审查者需要知道改了什么、为什么这样改 |
| Reviewer → Tester | `files_modified`, `issues_encountered`（来自 review）, `summary` | 测试者需要知道测什么文件、有哪些已知问题 |
| Tester → Acceptor | `summary`（全阶段）, `issues_encountered`, `handoff_notes` | 验收者需要全局概览 |
| 任意 → Designer（重设计） | `issues_encountered`, `handoff_notes`, `summary` | 设计者需要知道失败原因 |

**格式化输出模板**：

```markdown
## 📋 任务记忆: T-008 — 自动记忆捕获

### 上阶段摘要
设计了基于 hook 检测的自动记忆捕获机制...

### 关键决策
- 采用 hook 检测 + Agent 提取的混合方案
- 记忆格式兼容现有 T-NNN-memory.json

### 产出物
- `.agents/runtime/designer/workspace/design-docs/T-008-auto-memory-capture.md`

### 交接要点
> 实现者需先修改 hook 脚本，再更新 SKILL.md
```

### API / Interface

**agent-switch SKILL.md 新增逻辑**：

在"切换角色"操作的步骤中，增加第 4 步"智能记忆加载"：

```markdown
### 智能记忆加载

切换到目标 Agent 后，自动执行：
1. 从 task-board.json 查找该 Agent 当前被分配的任务
2. 读取 `.agents/memory/T-NNN-memory.json`
3. 根据角色映射表提取相关字段
4. 格式化为 Markdown 摘要
5. 在 Agent 启动信息中展示

#### 角色映射规则
（见上方映射表）

#### 输出格式
使用简洁 Markdown，不展示原始 JSON。包含标题、分节、列表。
```

**agent-memory SKILL.md 新增章节**：

```markdown
### 智能加载（Smart Loading）

记忆可按角色需求差异化加载。加载时不直接展示 JSON，而是格式化为可读摘要。
详见 agent-switch SKILL.md "智能记忆加载" 章节。
```

### Implementation Steps

1. **定义角色-字段映射表**：
   - 在 `skills/agent-switch/SKILL.md` 中新增"智能记忆加载"章节
   - 以 Markdown 表格形式定义 5 种角色转换路径对应的字段列表

2. **更新 agent-switch 切换逻辑**：
   - 在现有"切换角色"步骤（读取 inbox 之后）增加记忆加载步骤
   - 流程：查找任务 → 读取记忆文件 → 按映射过滤 → 格式化输出

3. **定义 Markdown 格式化模板**：
   - 在 `skills/agent-switch/SKILL.md` 中提供格式化模板
   - 模板包含：任务标题、上阶段摘要、关键决策（列表）、产出物（列表）、交接要点（引用块）
   - 仅展示映射表中指定的字段，其余字段不加载

4. **处理边界情况**：
   - 无记忆文件：跳过加载，显示"暂无历史记忆"
   - 记忆文件为空或字段缺失：只展示有值的字段
   - 无分配任务：跳过加载

5. **更新 `skills/agent-memory/SKILL.md`**：
   - 新增"智能加载（Smart Loading）"章节
   - 说明记忆按角色差异化加载的机制
   - 引用 agent-switch SKILL.md 的具体规则

6. **更新 `skills/agent-switch/SKILL.md`**：
   - 在"查看所有 Agent 状态"部分，说明切换时自动加载记忆
   - 在各角色处理逻辑中补充记忆加载说明

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | 切换到 Implementer，存在 Designer 阶段记忆 | 输出包含 decisions, artifacts, handoff_notes，不含 issues_encountered |
| 2 | 切换到 Reviewer，存在 Implementer 阶段记忆 | 输出包含 files_modified, decisions，不含 artifacts |
| 3 | 切换到 Tester，存在 Reviewer 阶段记忆 | 输出包含 files_modified, issues（review），不含 decisions |
| 4 | 切换到 Agent，无记忆文件 | 显示"暂无历史记忆"，正常继续 |
| 5 | 切换到 Agent，无分配任务 | 跳过记忆加载 |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 6 | 完整流程：Designer 保存记忆 → 切换到 Implementer | Implementer 上下文包含格式化的设计摘要 |
| 7 | 记忆格式验证 | 输出为 Markdown 格式，非 JSON |
| 8 | Token 效率测试 | 智能加载的输出长度 < 全量加载的 50% |

### 验收标准

- [ ] G1: agent-switch 切换时自动加载任务记忆
- [ ] G2: 按角色映射表过滤字段（至少覆盖 5 种转换路径）
- [ ] G3: 输出为 Markdown 摘要格式，非原始 JSON
- [ ] G4: agent-memory 和 agent-switch SKILL.md 均已更新

## Consequences

**正面**：
- Agent 启动时自动获得精准上下文，减少 token 浪费
- Markdown 格式比 JSON 更易于 Agent 理解和利用
- 角色映射表可维护、可扩展

**负面/风险**：
- 映射表需要随角色数量增长而维护
- 格式化模板可能需要迭代调整

**依赖**：
- 依赖 T-008 的标准化记忆格式（auto-capture 产出的 memory.json）

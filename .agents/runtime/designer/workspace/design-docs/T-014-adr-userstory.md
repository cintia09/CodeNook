# T-014: Designer 添加 ADR 格式，Acceptor 添加用户故事格式

## Context

当前框架中：
1. **Designer 的设计文档模板**缺少 ADR（Architecture Decision Record）格式——没有明确的"决策"、"替代方案"和"后果"章节，导致设计决策的理由和权衡不够透明
2. **Designer 没有目标覆盖自查机制**——设计文档可能遗漏某些 Goal 的对应设计
3. **Acceptor 的需求格式**缺少用户故事模板——Goal 描述偏向技术实现，缺少用户视角（谁用、为什么用、带来什么价值）

## Decision

1. 在 `agent-designer SKILL.md` 中升级设计文档模板为 ADR 格式
2. 在 `agent-designer SKILL.md` 中增加"目标覆盖自查"步骤
3. 在 `agent-acceptor SKILL.md` 中增加"用户故事格式"指导

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: SKILL.md 模板升级（选中）** | 与现有框架一致，渐进式改进 | 需要更新已有文档习惯 | ✅ 选中 |
| **B: 独立的 ADR 目录** | ADR 集中管理 | 与设计文档分离，增加维护点 | ❌ 分散管理 |
| **C: 仅更新模板，不加自查** | 更简单 | 遗漏 Goal 的问题仍存在 | ❌ 不彻底 |
| **D: 引入 JIRA 格式的 ticket** | 业界标准 | 过于重量级，不适合轻量框架 | ❌ 过度工程化 |

## Design

### Architecture

```
变更范围：

skills/agent-designer/SKILL.md
├── 现有: 设计文档模板（8 个章节）
│   └── 升级为 ADR 格式（增加 Decision, Alternatives, Consequences）
├── 新增: 目标覆盖自查步骤
│   └── 设计完成前验证每个 Goal 有对应设计章节
└── 现有: Flow A / Flow B
    └── 流程中引用新模板和自查步骤

skills/agent-acceptor/SKILL.md
├── 现有: 功能目标定义规则
│   └── 新增: 用户故事格式指导
└── 现有: Flow A: 收集需求
    └── 流程中引用用户故事格式
```

### Data Model

**ADR 增强的设计文档模板**：

```markdown
# T-NNN: <标题>

## Context
描述问题背景、当前状态和痛点。回答"为什么需要这个变更？"

## Decision
明确说明决策内容。回答"我们决定怎么做？"

## Alternatives Considered
| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| A: <方案名>（选中） | ... | ... | ✅ 选中 |
| B: <方案名> | ... | ... | ❌ <原因> |
| C: <方案名> | ... | ... | ❌ <原因> |

## Design
### Architecture
系统架构图或模块关系图（ASCII 图优先）

### Data Model（如适用）
数据结构定义、JSON Schema、数据库模型

### API / Interface
对外接口定义、SKILL.md 变更说明

### Implementation Steps（编号，足够具体让实现者执行）
1. 具体步骤 1...
2. 具体步骤 2...

## Test Spec
| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | ... | ... |

### 验收标准
- [ ] G1: ...
- [ ] G2: ...

## Consequences
### 正面
- ...

### 负面/风险
- ...

### 后续影响
- ...
```

**目标覆盖自查表**：

```markdown
## 目标覆盖自查

| Goal ID | Goal 描述 | 对应设计章节 | 覆盖状态 |
|---------|----------|-------------|---------|
| G1 | ... | Design > Architecture | ✅ 已覆盖 |
| G2 | ... | Design > API / Interface | ✅ 已覆盖 |
| G3 | ... | （缺失） | ❌ 未覆盖 — 需补充 |
```

**用户故事格式**：

```markdown
### Goal 定义格式

每个 Goal 使用用户故事格式：

**As a** [角色/使用者],
**I want** [期望的功能/行为],
**So that** [带来的价值/好处].

#### 示例
- **As a** 项目管理者,
  **I want** 在 `/agent status` 中看到 ASCII 流水线图,
  **So that** 我无需查看 JSON 文件即可了解任务进度.

- **As a** 下游 Agent,
  **I want** 切换时自动加载角色相关的记忆摘要,
  **So that** 我无需阅读完整记忆文件即可获得足够上下文.

#### 验收条件格式
每个 Goal 附带可验证的验收条件：
**Given** [前提条件], **When** [操作], **Then** [预期结果].
```

### API / Interface

**agent-designer SKILL.md 变更**：

1. **替换现有设计文档模板**：
   - 原模板 8 个章节 → ADR 格式（Context, Decision, Alternatives, Design, Test Spec, Consequences）
   - Design 下保留子章节：Architecture, Data Model, API/Interface, Implementation Steps

2. **新增"目标覆盖自查"步骤**：
   - 在 Flow A 的"完成设计文档"步骤后，新增"目标覆盖自查"步骤
   - 设计者必须在提交前填写自查表，确认每个 Goal 有对应设计

**agent-acceptor SKILL.md 变更**：

1. **新增"用户故事格式"章节**：
   - 在"功能目标定义规则"之后新增
   - 定义 As a / I want / So that 格式
   - 定义 Given / When / Then 验收条件格式
   - 提供 2-3 个示例

### Implementation Steps

1. **更新 `skills/agent-designer/SKILL.md` — 设计文档模板**：
   - 将现有设计文档模板替换为 ADR 增强版
   - 新模板包含：Context, Decision, Alternatives Considered, Design（含子章节）, Test Spec, Consequences
   - 每个章节包含填写指导说明

2. **新增"目标覆盖自查"机制**：
   - 在 SKILL.md 的 Flow A 中，"完成设计文档"步骤后增加"目标覆盖自查"步骤
   - 定义自查表格式：Goal ID → 对应设计章节 → 覆盖状态
   - 所有 Goal 必须为"✅ 已覆盖"才能提交设计

3. **更新 `skills/agent-acceptor/SKILL.md` — 用户故事格式**：
   - 在"功能目标定义规则"章节后新增"用户故事格式"子章节
   - 定义 As a / I want / So that 模板
   - 定义 Given / When / Then 验收条件模板
   - 提供与本项目相关的示例（Agent 场景）

4. **更新 Flow A 中的模板引用**：
   - Designer Flow A 第 3 步引用新的 ADR 模板
   - Acceptor Flow A 第 2 步引用用户故事格式

5. **确保向后兼容**：
   - 现有设计文档不需要重写
   - 新模板是增量增强，不改变现有字段的含义

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | agent-designer SKILL.md 包含 ADR 模板 | 模板包含 Context, Decision, Alternatives, Consequences 章节 |
| 2 | agent-designer SKILL.md 包含目标覆盖自查 | 自查表格式定义明确，包含 Goal ID/设计章节/覆盖状态 |
| 3 | agent-acceptor SKILL.md 包含用户故事格式 | 包含 As a / I want / So that 模板 |
| 4 | agent-acceptor SKILL.md 包含验收条件格式 | 包含 Given / When / Then 模板 |
| 5 | ADR 模板向后兼容 | 现有设计文档的必要字段均在新模板中保留 |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 6 | Designer 使用新模板创建设计文档 | 文档包含所有 ADR 章节 |
| 7 | Designer 执行目标覆盖自查 | 自查表列出所有 Goal 及对应设计章节 |
| 8 | 自查发现 Goal 未覆盖 | 阻止提交，要求补充设计 |
| 9 | Acceptor 使用用户故事格式定义 Goal | Goal 描述包含角色、行为、价值 |

### 验收标准

- [ ] G1: agent-designer SKILL.md 设计文档模板包含 ADR 章节（Decision, Context, Alternatives, Consequences）
- [ ] G2: agent-designer 新增目标覆盖自查步骤，验证每个 Goal 有对应设计
- [ ] G3: agent-acceptor SKILL.md 包含用户故事格式指导（As a / I want / So that）

## Consequences

**正面**：
- 设计决策透明化，后续维护者可理解"为什么这样设计"
- 替代方案记录有助于未来重新评估决策
- 目标覆盖自查减少设计遗漏
- 用户故事格式让需求更聚焦于价值而非实现细节

**负面/风险**：
- ADR 格式增加设计文档的编写时间
- 用户故事格式对于纯技术任务可能略显牵强

**后续影响**：
- 本任务（T-014）的设计文档本身即采用了 ADR 格式，是自身的最佳实践验证
- 未来所有 T-008 ~ T-013 的设计文档都应采用此格式

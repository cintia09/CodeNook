# T-010: Agent 状态面板中的 ASCII 流水线可视化

## Context

当前 `/agent status` 输出只显示 Agent 列表和简单的任务信息，无法直观看到每个任务在流水线中的位置。用户需要手动查看 `task-board.json` 才能了解任务进度。

多 Agent 框架的核心流程是 5 阶段流水线：Design → Implement → Review → Test → Accept。将这个流水线以 ASCII 图形展示在状态面板中，可以大幅提升项目可见性。

## Decision

在 `agent-switch` 的 `/agent status` 输出中增加 ASCII 流水线图。每个活跃任务独立一行，用 emoji 和状态标记展示当前位置。

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: 内联 ASCII 流水线（选中）** | 终端兼容性好、信息密度高 | 宽度有限，任务多时较长 | ✅ 选中 |
| **B: 表格形式展示** | 结构清晰 | 不够直观，看不出流向 | ❌ 缺少流水线感 |
| **C: 外部 HTML 报告** | 可视化效果最好 | 需要额外工具，脱离终端 | ❌ 增加依赖 |
| **D: 仅文字描述** | 最简单 | 信息密度低，不直观 | ❌ 现状已如此 |

## Design

### Architecture

```
/agent status 输出结构（增强后）：

╔══════════════════════════════════════════╗
║  🤖 Multi-Agent Pipeline Status          ║
╠══════════════════════════════════════════╣
║                                          ║
║  T-008: 自动记忆捕获                      ║
║  📐Design ──→ 🔨Implement ──→ 🔍Review   ║
║    ✅          ⏳ ◀──当前      ⏸️          ║
║  ──→ 🧪Test ──→ ✅Accept                 ║
║       ⏸️          ⏸️                      ║
║                                          ║
║  T-009: 智能记忆加载                      ║
║  📐Design ──→ 🔨Implement ──→ 🔍Review   ║
║    ⏳ ◀──当前   ⏸️            ⏸️          ║
║  ──→ 🧪Test ──→ ✅Accept                 ║
║       ⏸️          ⏸️                      ║
║                                          ║
╚══════════════════════════════════════════╝
```

**状态图标定义**：
- ✅ 已完成（done）
- ⏳ 进行中（active / 当前阶段）
- ⏸️ 等待中（pending / 未开始）
- 🚫 已阻塞（blocked）
- ❌ 失败需重做（rejected）

**阶段 emoji**：
- 📐 Design（设计）
- 🔨 Implement（实现）
- 🔍 Review（审查）
- 🧪 Test（测试）
- ✅ Accept（验收）

### Data Model

**状态到阶段的映射**：

```
FSM Status      → Pipeline Stage    → Display
─────────────────────────────────────────────
created         → (pre-pipeline)    → 未进入流水线
designing       → Design            → ⏳
implementing    → Implement         → ⏳
reviewing       → Review            → ⏳
testing         → Test              → ⏳
accepting       → Accept            → ⏳
accepted        → Accept            → ✅（全流程完成）
blocked         → (当前阶段)        → 🚫
```

**阶段完成推断规则**：
- 如果当前状态是 `implementing`，则 `Design` 阶段为 ✅
- 如果当前状态是 `reviewing`，则 `Design` + `Implement` 为 ✅
- 依此类推：当前阶段之前的所有阶段标记为 ✅

### API / Interface

**agent-switch SKILL.md 新增章节**：

```markdown
### 流水线可视化

在 `/agent status` 输出中，为每个活跃任务展示 ASCII 流水线：

#### 渲染规则
1. 从 task-board.json 读取所有非 `accepted` 且非 `created` 的任务
2. 对每个任务，根据 status 确定当前阶段
3. 当前阶段标记 ⏳ + ◀──当前
4. 之前的阶段标记 ✅
5. 之后的阶段标记 ⏸️
6. blocked 状态在对应阶段标记 🚫

#### 输出格式
每个任务占 4 行：
- 第 1 行：任务 ID + 标题
- 第 2 行：前 3 个阶段（Design → Implement → Review）
- 第 3 行：对应状态图标
- 第 4 行：后 2 个阶段（Test → Accept）+ 状态图标
```

**紧凑模式**（任务 > 5 个时自动切换）：

```
T-008: 自动记忆捕获   [📐✅──🔨⏳──🔍⏸️──🧪⏸️──✅⏸️]
T-009: 智能记忆加载   [📐⏳──🔨⏸️──🔍⏸️──🧪⏸️──✅⏸️]
```

### Implementation Steps

1. **定义阶段常量和映射**：
   - 在 `skills/agent-switch/SKILL.md` 中定义 5 阶段名称、emoji、FSM 状态映射
   - 定义状态图标（✅⏳⏸️🚫❌）

2. **设计渲染逻辑**：
   - 在 `/agent status` 的说明中新增"流水线可视化"章节
   - 描述渲染算法：读取任务列表 → 过滤活跃任务 → 计算每个阶段状态 → 输出 ASCII

3. **实现标准模式渲染**：
   - 每个任务 4 行输出
   - 阶段间用 `──→` 连接
   - 当前阶段追加 `◀──当前` 标记

4. **实现紧凑模式渲染**：
   - 任务数 > 5 时自动切换
   - 每个任务单行：`[📐✅──🔨⏳──🔍⏸️──🧪⏸️──✅⏸️]`

5. **处理特殊状态**：
   - `blocked`: 在对应阶段位置显示 🚫，并附加 blocked_reason
   - `accepted`: 全部 ✅，标注"已完成"
   - `created`: 不进入流水线展示（或标注"待启动"）

6. **更新 `skills/agent-switch/SKILL.md`**：
   - 在"查看所有 Agent 状态"操作中集成流水线输出
   - 添加完整的渲染规则和示例输出

7. **已完成任务的展示策略**：
   - `accepted` 状态的任务默认折叠，仅显示一行摘要
   - 可通过 `/agent status --all` 展开全部

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | 单个任务处于 `implementing` | 流水线显示 Design✅, Implement⏳, Review⏸️, Test⏸️, Accept⏸️ |
| 2 | 单个任务处于 `reviewing` | Design✅, Implement✅, Review⏳, Test⏸️, Accept⏸️ |
| 3 | 任务处于 `blocked`（从 implementing） | Design✅, Implement🚫, Review⏸️, Test⏸️, Accept⏸️ |
| 4 | 任务已 `accepted` | 全部 ✅ |
| 5 | 任务为 `created` | 不出现在流水线中（或标注"待启动"） |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 6 | 3 个活跃任务在不同阶段 | 各自独立的流水线行，标准模式 |
| 7 | 6 个活跃任务 | 自动切换紧凑模式，每任务一行 |
| 8 | `/agent status` 整体输出 | 流水线在 Agent 列表之后展示，格式正确无错位 |

### 验收标准

- [ ] G1: `/agent status` 包含 ASCII 流水线图，显示 5 阶段和当前位置
- [ ] G2: 每个任务显示阶段名、emoji、状态图标（✅/⏳/⏸️）
- [ ] G3: 多个活跃任务各有独立流水线行
- [ ] G4: agent-switch SKILL.md 包含流水线可视化规范

## Consequences

**正面**：
- 项目进度一目了然，无需查看 JSON 文件
- 紧凑模式确保大量任务时仍可读
- Emoji + ASCII 在各种终端都能正常显示

**负面/风险**：
- 终端宽度不足时可能换行导致错位
- Emoji 在不同终端的宽度可能不一致

**后续影响**：
- 为未来的 Web Dashboard 提供数据模型参考

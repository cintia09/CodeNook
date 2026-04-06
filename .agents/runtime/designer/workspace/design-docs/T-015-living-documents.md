# T-015: 项目级活文档系统

## Context (背景)

当前框架中，每个任务的文档散落在各 Agent 的 workspace 子目录下：

- 需求文档: `.agents/runtime/acceptor/workspace/requirements/T-NNN-requirement.md`
- 设计文档: `.agents/runtime/designer/workspace/design-docs/T-NNN-design.md`
- 测试规格: `.agents/runtime/designer/workspace/test-specs/T-NNN-test-spec.md`
- 审查报告: `.agents/runtime/reviewer/workspace/review-reports/T-NNN-review.md`
- 验收报告: `.agents/runtime/acceptor/workspace/acceptance-reports/T-NNN-report.md`

这种碎片化存储带来三个问题：

1. **缺乏全局视图**：无法一次性纵览所有任务的需求、设计、测试、实现历程，必须在多层目录间跳转
2. **知识不累积**：每个任务独立文件，后续任务无法从前序任务的设计决策中受益
3. **跨 Agent 信息断层**：Tester 写测试规格时需手动定位 requirement 和 design 两个不同目录的文件；Reviewer 无法快速了解上游设计意图

`docs/` 目录当前仅有 `agent-rules.md`（协作规则），没有按任务累积的项目级文档。

## Decision (决策)

在 `docs/` 目录创建 6 个**项目级活文档**（living documents），由对应 Agent 在完成各自任务阶段后自动追加新章节：

| 文档 | 维护者 | 追加时机 |
|------|--------|---------|
| `docs/requirement.md` | Acceptor | 流程 A 完成（需求发布后） |
| `docs/design.md` | Designer | 流程 A 完成（设计完成后） |
| `docs/test-spec.md` | Tester | 流程 A 测试用例生成后 |
| `docs/implementation.md` | Implementer | 流程 A 实现完成后 |
| `docs/review.md` | Reviewer | 审查完成后（通过或退回） |
| `docs/acceptance.md` | Acceptor | 流程 B 验收完成后（通过或失败） |

文档是**累积式**的——每次追加 `## T-NNN: <title>` 新章节，不覆盖已有内容。

## Alternatives Considered (备选方案)

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: docs/ 活文档（选中）** | 全局视图集中、Git 可追溯、Agent 自动维护 | 文件会随任务数增长 | ✅ 选中 |
| **B: 每任务独立文档集** | 隔离性好 | 即当前方案，缺乏全局视图和知识累积 | ❌ 现状问题不解决 |
| **C: SQLite 数据库存储** | 查询灵活 | 可读性差，不适合人类阅读和 Git diff | ❌ 可读性牺牲 |
| **D: 单一 CHANGELOG.md** | 简单 | 六种文档类型混在一起，难以定位特定信息 | ❌ 粒度过粗 |
| **E: Wiki 系统** | 功能丰富 | 引入外部依赖，超出轻量框架范围 | ❌ 过度工程化 |

## Design (设计)

### Architecture (架构)

```
文档写入流（每个任务阶段完成后触发）:

┌─────────────────────────────────────────────────────────┐
│  任务生命周期                                              │
│                                                          │
│  created ─────────────────────────────────────────────── │
│     │                                                    │
│     ▼  Acceptor 流程A 完成                                │
│  designing ──┬── 追加 docs/requirement.md                 │
│     │        │   ## T-NNN: <title>                       │
│     ▼        │                                           │
│  implementing ── Designer 流程A 完成                      │
│     │        ├── 追加 docs/design.md                      │
│     │        │   ## T-NNN: <title>                       │
│     ▼        │                                           │
│  reviewing ──── Implementer 流程A 完成                    │
│     │        ├── 追加 docs/implementation.md              │
│     │        │   ## T-NNN: <title>                       │
│     ▼        │                                           │
│  testing ────── Reviewer 审查完成                         │
│     │        ├── 追加 docs/review.md                      │
│     │        │   ## T-NNN: <title>                       │
│     ▼        │                                           │
│  accepting ──── Tester 流程A 完成                         │
│     │        ├── 追加 docs/test-spec.md                   │
│     │        │   ## T-NNN: <title>                       │
│     ▼        │                                           │
│  accepted ───── Acceptor 流程B 完成                       │
│              └── 追加 docs/acceptance.md                  │
│                  ## T-NNN: <title>                       │
└─────────────────────────────────────────────────────────┘

Tester 写入 test-spec.md 前的输入依赖:

  docs/requirement.md ──┐
                        ├──→ Tester 读取 → 生成 test-spec 章节
  docs/design.md ───────┘

agent-init 初始化时:

  Step 2 (创建目录结构) 新增:
  ┌──────────────────────────────┐
  │  docs/                       │
  │  ├── agent-rules.md  (已有)  │
  │  ├── requirement.md  (新建)  │
  │  ├── design.md       (新建)  │
  │  ├── test-spec.md    (新建)  │
  │  ├── implementation.md(新建) │
  │  ├── review.md       (新建)  │
  │  └── acceptance.md   (新建)  │
  └──────────────────────────────┘
```

**变更范围**：

```
新增文件（agent-init 创建空模板）:
  docs/requirement.md
  docs/design.md
  docs/test-spec.md
  docs/implementation.md
  docs/review.md
  docs/acceptance.md

修改文件（SKILL.md 增加活文档追加步骤）:
  skills/agent-acceptor/SKILL.md     — 流程A末尾 + 流程B末尾
  skills/agent-designer/SKILL.md     — 流程A末尾
  skills/agent-tester/SKILL.md       — 流程A步骤3前增加读取 + 完成后追加
  skills/agent-implementer/SKILL.md  — 流程A末尾
  skills/agent-reviewer/SKILL.md     — 审查流程末尾

修改文件（agent-init 增加模板创建步骤）:
  skills/agent-init/SKILL.md         — Step 2 增加 docs/ 模板创建

验证脚本更新:
  scripts/verify-init.sh             — 增加 docs/ 6 个文件的存在性检查
```

### Data Model (数据模型)

#### 活文档通用结构

每个活文档遵循相同的顶层结构：

```markdown
# <文档类型中文名>

> 本文档由 <Agent 角色> 自动维护，每完成一个任务阶段后追加新章节。请勿手动编辑。

---

## T-001: <任务标题>

<该文档类型特定的子章节>

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| 2026-04-10 | 创建 | 初始版本 |

---

## T-002: <另一个任务标题>

...
```

**累积规则**：
- 新章节**追加到文件末尾**（在最后一个 `---` 分隔符之后）
- 每个任务章节以 `---`（水平线）分隔
- 章节标题固定格式：`## T-NNN: <task-board.json 中的 title>`
- 同一任务可追加多次（如验收失败后重新设计，Designer 追加修订章节，标题为 `## T-NNN: <title>（修订 R2）`）

### Template Specs (模板规格)

#### 1. docs/requirement.md — 需求文档（Acceptor 维护）

初始模板（agent-init 创建）：

```markdown
# 需求文档

> 本文档由验收者 (Acceptor) 自动维护，每次发布新任务后追加需求章节。请勿手动编辑。
```

追加章节模板（Acceptor 流程A 第 6 步之后写入）：

```markdown
---

## T-NNN: <任务标题>

### 背景
<需求的业务背景，从 T-NNN-requirement.md 提取核心内容>

### 功能目标
| Goal ID | 描述 | 优先级 |
|---------|------|--------|
| G1 | <目标描述> | <高/中/低> |
| G2 | <目标描述> | <高/中/低> |

### 验收标准
<从 T-NNN-acceptance.md 提取关键验收条件>

### 非功能要求
<性能、安全、兼容性等要求，无则写"无特殊要求">

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 创建 | 需求发布，含 N 个功能目标 |
```

**Acceptor 写入指导**：
- 信息来源：`acceptor/workspace/requirements/T-NNN-requirement.md` + `task-board.json` 中的 goals 数组
- 不是复制粘贴原文件，而是**提取核心摘要**（控制在 30-50 行以内）
- 功能目标表必须与 task-board.json 中的 goals 一一对应

#### 2. docs/design.md — 设计文档（Designer 维护）

初始模板：

```markdown
# 设计文档

> 本文档由设计者 (Designer) 自动维护，每次完成任务设计后追加设计章节。请勿手动编辑。
```

追加章节模板（Designer 流程A 第 7 步之前写入）：

```markdown
---

## T-NNN: <任务标题>

### 决策摘要
<一段话概括核心设计决策>

### 架构变更
<本次设计涉及的模块/文件变更概览，ASCII 图优先>

### 关键设计点
1. <设计点 1: 方案选择及理由>
2. <设计点 2: 方案选择及理由>

### 文件变更清单
| 文件路径 | 操作 | 说明 |
|---------|------|------|
| `path/to/file` | 新增/修改/删除 | <变更说明> |

### 详细设计引用
完整设计文档: `.agents/runtime/designer/workspace/design-docs/T-NNN-*.md`

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 创建 | 设计完成，覆盖 N 个 Goal |
```

**Designer 写入指导**：
- 信息来源：刚完成的 `designer/workspace/design-docs/T-NNN-*.md`
- 是**摘要版**，不是完整设计文档的复制——保留决策和架构变更，省略详细实现步骤
- 必须包含文件变更清单（Implementer 和 Tester 需要知道影响范围）
- 如果是修订（流程B），章节标题改为 `## T-NNN: <title>（修订 RN）`，在 Changelog 追加修订记录

#### 3. docs/test-spec.md — 测试规格（Tester 维护）

初始模板：

```markdown
# 测试规格

> 本文档由测试者 (Tester) 自动维护，每次生成测试用例后追加测试规格章节。请勿手动编辑。
```

追加章节模板（Tester 流程A 第 4 步之后写入）：

```markdown
---

## T-NNN: <任务标题>

### 输入文档
- 需求: docs/requirement.md → T-NNN 章节
- 设计: docs/design.md → T-NNN 章节

### 测试矩阵
| # | 测试场景 | 类型 | 覆盖 Goal | 预期结果 |
|---|---------|------|----------|---------|
| 1 | <场景描述> | 单元/集成/E2E | G1 | <预期> |
| 2 | <场景描述> | 单元/集成/E2E | G1, G2 | <预期> |

### 边界条件与异常
| # | 边界/异常场景 | 预期行为 |
|---|-------------|---------|
| 1 | <边界条件> | <预期> |

### 测试用例位置
`tester/workspace/test-cases/T-NNN/`

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 创建 | N 个测试场景，覆盖 N 个 Goal |
```

**Tester 写入指导**：
- **写入前必须先读取** `docs/requirement.md` 和 `docs/design.md` 中对应 T-NNN 章节
- 测试矩阵中的"覆盖 Goal"列必须引用 requirement.md 中定义的 Goal ID
- 确保每个 Goal 至少被一个测试场景覆盖
- 如果验证修复（流程B），追加修复验证记录到已有 T-NNN 章节的 Changelog 中

#### 4. docs/implementation.md — 实现文档（Implementer 维护）

初始模板：

```markdown
# 实现文档

> 本文档由实现者 (Implementer) 自动维护，每次完成任务实现后追加实现章节。请勿手动编辑。
```

追加章节模板（Implementer 流程A 第 8 步 git commit 之后写入）：

```markdown
---

## T-NNN: <任务标题>

### 实现摘要
<一段话概括实现方式和关键技术选择>

### 完成的 Goals
| Goal ID | 描述 | 实现方式 | Commit |
|---------|------|---------|--------|
| G1 | <目标描述> | <简述实现方式> | `abc1234` |
| G2 | <目标描述> | <简述实现方式> | `def5678` |

### 变更文件统计
- 新增: N 个文件
- 修改: N 个文件
- 删除: N 个文件

### 技术债务与注意事项
<实现过程中发现的技术债务、临时方案、已知限制，无则写"无">

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 创建 | N/N Goals 完成，覆盖率 XX% |
```

**Implementer 写入指导**：
- 在 `git commit` 完成之后、FSM 状态转移之前写入
- Goal 完成表必须与 task-board.json 中的 goals 状态一致
- Commit 列填写实际的 git commit hash 短码
- 如果是修复 Bug（流程B），在已有 T-NNN 章节的 Changelog 中追加修复记录

#### 5. docs/review.md — 审查文档（Reviewer 维护）

初始模板：

```markdown
# 审查文档

> 本文档由审查者 (Reviewer) 自动维护，每次完成代码审查后追加审查章节。请勿手动编辑。
```

追加章节模板（Reviewer 审查流程第 6 步之后写入）：

```markdown
---

## T-NNN: <任务标题>

### 审查结论: ✅ 通过 / ❌ 退回

### 审查范围
变更文件: N 个，+X / -Y 行

### 发现的问题
| # | 严重性 | 文件 | 描述 | 状态 |
|---|--------|------|------|------|
| 1 | 必须修复 | `path/file` | <问题描述> | 未修复/已修复 |

（无问题时写"无问题发现"）

### 质量评价
- 构建: ✅/❌
- 测试: ✅/❌
- Lint: ✅/❌

### 详细报告引用
完整审查报告: `.agents/runtime/reviewer/workspace/review-reports/T-NNN-review.md`

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 审查 | 结论: 通过/退回，N 个问题 |
```

**Reviewer 写入指导**：
- 在审查报告输出之后、FSM 状态转移之前写入
- 如果审查退回后再次审查，在已有 T-NNN 章节的 Changelog 中追加新审查记录，并更新问题状态列

#### 6. docs/acceptance.md — 验收文档（Acceptor 维护）

初始模板：

```markdown
# 验收文档

> 本文档由验收者 (Acceptor) 自动维护，每次完成验收后追加验收章节。请勿手动编辑。
```

追加章节模板（Acceptor 流程B 第 6/7 步之后写入）：

```markdown
---

## T-NNN: <任务标题>

### 验收结论: ✅ 通过 / ❌ 失败

### Goals 验收结果
| Goal ID | 描述 | 验收结果 | 备注 |
|---------|------|---------|------|
| G1 | <目标描述> | ✅ verified / ❌ failed | <失败原因或通过说明> |
| G2 | <目标描述> | ✅ verified / ❌ failed | <备注> |

### 验收总结
<整体评价，包括超出预期的亮点或需要后续改进的事项>

### 详细报告引用
完整验收报告: `.agents/runtime/acceptor/workspace/acceptance-reports/T-NNN-report.md`

### Changelog
| 日期 | 操作 | 说明 |
|------|------|------|
| <ISO日期> | 验收 | 结论: 通过/失败，N/M Goals verified |
```

**Acceptor 写入指导**：
- Goals 验收结果必须与 task-board.json 中 goals 的 verified/failed 状态一致
- 如果验收失败后再次验收，在已有 T-NNN 章节的 Changelog 中追加新验收记录

### Implementation Steps (实施步骤)

#### Step 1: 创建 6 个活文档初始模板文件

在项目 `docs/` 目录下创建以下 6 个文件，内容为各自的初始模板（仅包含标题和说明行，无任务章节）：

| 文件 | 标题行 | 说明行中的 Agent 角色 |
|------|--------|---------------------|
| `docs/requirement.md` | `# 需求文档` | 验收者 (Acceptor) |
| `docs/design.md` | `# 设计文档` | 设计者 (Designer) |
| `docs/test-spec.md` | `# 测试规格` | 测试者 (Tester) |
| `docs/implementation.md` | `# 实现文档` | 实现者 (Implementer) |
| `docs/review.md` | `# 审查文档` | 审查者 (Reviewer) |
| `docs/acceptance.md` | `# 验收文档` | 验收者 (Acceptor) |

每个文件的初始内容格式：

```markdown
# <标题>

> 本文档由<Agent 角色>自动维护，每完成一个任务阶段后追加新章节。请勿手动编辑。
```

#### Step 2: 更新 skills/agent-init/SKILL.md

在 **Step 2 (创建目录结构)** 部分的 `mkdir -p` 命令块之后，新增活文档模板创建步骤。

**具体插入位置**：在现有 Step 2 末尾（`mkdir -p .agents/runtime/tester/workspace/{test-cases,test-screenshots}` 之后），Step 3 之前。

**插入内容**：

````markdown
### 2b. 创建 docs/ 活文档模板

如果 `docs/` 目录不存在则创建:

```bash
mkdir -p docs
```

为以下 6 个活文档创建初始模板（**仅在文件不存在时创建，不覆盖已有内容**）：

| 文件 | 初始内容 |
|------|---------|
| `docs/requirement.md` | `# 需求文档` + 验收者维护说明 |
| `docs/design.md` | `# 设计文档` + 设计者维护说明 |
| `docs/test-spec.md` | `# 测试规格` + 测试者维护说明 |
| `docs/implementation.md` | `# 实现文档` + 实现者维护说明 |
| `docs/review.md` | `# 审查文档` + 审查者维护说明 |
| `docs/acceptance.md` | `# 验收文档` + 验收者维护说明 |

每个文件的初始内容为两行：
```markdown
# <标题>

> 本文档由<角色>自动维护，每完成一个任务阶段后追加新章节。请勿手动编辑。
```

创建逻辑：
```bash
# 对每个文件，仅在不存在时创建
[ ! -f docs/requirement.md ] && echo '创建 docs/requirement.md'
[ ! -f docs/design.md ] && echo '创建 docs/design.md'
# ... 其余 4 个类推
```
````

同时在 **Step 7 (输出摘要)** 的输出模板中增加一行：

```
活文档: docs/ (6 living documents)
```

#### Step 3: 更新 skills/agent-acceptor/SKILL.md

**变更 1: 流程 A 追加活文档步骤**

在现有流程 A 的步骤编号序列中，在第 5 步（`使用 agent-task-board skill 创建任务`）和第 6 步（`更新 state.json`）之间，插入新步骤：

```
5b. 追加 docs/requirement.md — 在文件末尾追加 T-NNN 需求章节
    - 读取刚创建的 T-NNN-requirement.md 和 task-board.json 中的 goals 数组
    - 按 Template Specs 第 1 节的追加章节模板提取摘要内容
    - 追加到 docs/requirement.md 末尾（以 `---` 开始新章节）
```

**变更 2: 流程 B 追加活文档步骤**

在现有流程 B 中，在第 7 步（`如果所有 goals 都为 verified`）或第 8 步（`如果有任何 goal 为 failed`）中的 FSM 状态转移之后，各追加一步：

```
7b / 8b. 追加 docs/acceptance.md — 在文件末尾追加 T-NNN 验收章节
    - 读取验收报告和 task-board.json 中 goals 的 verified/failed 状态
    - 按 Template Specs 第 6 节的追加章节模板生成验收章节
    - 追加到 docs/acceptance.md 末尾
```

**变更 3: 新增"活文档维护规则"章节**

在"限制"章节之前（即第 99 行 `## 限制` 之前），新增以下完整章节：

```markdown
## 活文档维护规则

本 Agent 负责维护以下项目级活文档：
- `docs/requirement.md` — 流程A完成后追加需求章节
- `docs/acceptance.md` — 流程B完成后追加验收章节

### 追加规则
1. 在文件末尾追加，以 `---` 分隔符开始新章节
2. 章节标题: `## T-NNN: <task-board.json 中的 title>`
3. 内容为摘要（非全文复制），控制在 30-50 行
4. 必须包含 Changelog 表
5. 修订时在已有章节的 Changelog 表中追加记录，不创建新章节
```

#### Step 4: 更新 skills/agent-designer/SKILL.md

**变更 1: 流程 A 追加活文档步骤**

在现有流程 A 中，在第 6 步（`输出测试规格`）和第 7 步（`使用 agent-fsm`）之间，插入新步骤：

```
6b. 追加 docs/design.md — 在文件末尾追加 T-NNN 设计章节
    - 从刚完成的设计文档中提取: 决策摘要、架构变更、文件变更清单
    - 按 Template Specs 第 2 节的追加章节模板生成摘要章节
    - 追加到 docs/design.md 末尾
```

**变更 2: 流程 B 追加修订记录**

在现有流程 B 中，在第 4 步（`修订设计文档`）和第 5 步（`更新测试规格`）之间，新增：

```
4b. 更新 docs/design.md — 在 T-NNN 已有章节的 Changelog 表中追加修订记录
    - 如变更较小: 在已有 T-NNN 章节 Changelog 表追加行 `| <日期> | 修订 | R2: <修订原因摘要> |`
    - 如变更较大: 追加新章节，标题为 `## T-NNN: <title>（修订 R2）`
```

**变更 3: 新增"活文档维护规则"章节**

在"限制"章节之前（即第 89 行 `## 限制` 之前），新增：

```markdown
## 活文档维护规则

本 Agent 负责维护以下项目级活文档：
- `docs/design.md` — 流程A完成后追加设计摘要章节

### 追加规则
1. 在文件末尾追加，以 `---` 分隔符开始新章节
2. 章节标题: `## T-NNN: <task-board.json 中的 title>`
3. 内容为设计摘要（非完整设计文档），保留决策和架构变更
4. 必须包含文件变更清单（下游 Agent 需要知道影响范围）
5. 必须包含 Changelog 表
6. 修订时标注修订版本号（R2, R3...）
```

#### Step 5: 更新 skills/agent-tester/SKILL.md

**变更 1: 流程 A 增加活文档读取步骤**

将现有流程 A 的第 2-3 步：

```
2. 读取验收文档 (acceptor/workspace/acceptance-docs/T-NNN-acceptance.md)
3. 读取设计文档 + 测试规格
```

替换为：

```
2. 读取项目级活文档作为输入:
   a. 读取 docs/requirement.md → 找到 ## T-NNN 章节，提取功能目标和验收标准
   b. 读取 docs/design.md → 找到 ## T-NNN 章节，提取架构变更和文件变更清单
3. 补充读取详细文档（如活文档信息不足）:
   a. acceptor/workspace/acceptance-docs/T-NNN-acceptance.md
   b. designer/workspace/design-docs/T-NNN-*.md + test-specs/T-NNN-*.md
```

**变更 2: 流程 A 追加活文档步骤**

在现有流程 A 中，在第 5 步（`执行自动化测试`）和第 6/7 步（FSM 转移）之间，插入新步骤：

```
5b. 追加 docs/test-spec.md — 在文件末尾追加 T-NNN 测试规格章节
    - 标注输入来源: docs/requirement.md 和 docs/design.md 对应章节
    - 生成测试矩阵，每个测试场景标注覆盖的 Goal ID
    - 按 Template Specs 第 3 节的追加章节模板生成章节
    - 追加到 docs/test-spec.md 末尾
```

**变更 3: 新增"活文档维护规则"章节**

在"限制"章节之前，新增：

```markdown
## 活文档维护规则

本 Agent 负责维护以下项目级活文档：
- `docs/test-spec.md` — 流程A测试用例生成后追加测试规格章节

### 读取规则（写入前必须执行）
1. 读取 `docs/requirement.md` 中 `## T-NNN` 章节 → 提取 Goals 和验收标准
2. 读取 `docs/design.md` 中 `## T-NNN` 章节 → 提取架构变更和文件清单
3. 基于上述信息设计测试矩阵，确保每个 Goal 至少被一个测试覆盖

### 追加规则
1. 在文件末尾追加，以 `---` 分隔符开始新章节
2. 章节标题: `## T-NNN: <task-board.json 中的 title>`
3. 测试矩阵必须包含"覆盖 Goal"列
4. 必须包含 Changelog 表
5. 验证修复时在已有章节 Changelog 追加记录
```

#### Step 6: 更新 skills/agent-implementer/SKILL.md

**变更 1: 流程 A 追加活文档步骤**

在现有流程 A 中，在第 8 步（`git commit + push`）和第 9 步（`使用 agent-fsm 转为 reviewing`）之间，插入新步骤：

```
8b. 追加 docs/implementation.md — 在文件末尾追加 T-NNN 实现章节
    - 提取: goals 完成情况（从 task-board.json）+ git commit hashes + 文件变更统计（从 git diff --stat）
    - 记录技术债务和注意事项
    - 按 Template Specs 第 4 节的追加章节模板生成章节
    - 追加到 docs/implementation.md 末尾
```

**变更 2: 流程 B (修复 Bug) 追加记录**

在流程 B 完成修复、git commit 之后，新增：

```
Nb. 更新 docs/implementation.md — 在 T-NNN 已有章节的 Changelog 中追加修复记录
    - 格式: | <日期> | 修复 | 修复 issue #N: <摘要>, commit `<hash>` |
```

**变更 3: 新增"活文档维护规则"章节**

在"限制"章节之前，新增：

```markdown
## 活文档维护规则

本 Agent 负责维护以下项目级活文档：
- `docs/implementation.md` — 流程A实现完成后追加实现章节

### 追加规则
1. 在文件末尾追加，以 `---` 分隔符开始新章节
2. 章节标题: `## T-NNN: <task-board.json 中的 title>`
3. Goals 完成表中的 Commit 列必须填写实际 git commit hash 短码
4. 必须包含 Changelog 表
5. 修复 Bug 时在已有章节 Changelog 追加修复记录
```

#### Step 7: 更新 skills/agent-reviewer/SKILL.md

**变更 1: 审查流程追加活文档步骤**

在现有审查流程中，在第 6 步（`输出审查报告到 reviewer/workspace/review-reports/T-NNN-review.md`）之后，在第 7 步（`如果通过: agent-fsm 转为 testing`）之前，插入新步骤：

```
6b. 追加 docs/review.md — 在文件末尾追加 T-NNN 审查章节
    - 提取: 审查结论、问题列表、质量评价（构建/测试/Lint 结果）
    - 按 Template Specs 第 5 节的追加章节模板生成摘要章节
    - 追加到 docs/review.md 末尾
```

**变更 2: 新增"活文档维护规则"章节**

在"限制"章节之前（即第 77 行 `## 限制` 之前），新增：

```markdown
## 活文档维护规则

本 Agent 负责维护以下项目级活文档：
- `docs/review.md` — 审查完成后追加审查章节

### 追加规则
1. 在文件末尾追加，以 `---` 分隔符开始新章节
2. 章节标题: `## T-NNN: <task-board.json 中的 title>`
3. 审查退回后再次审查时，在已有章节 Changelog 追加新记录并更新问题状态
4. 必须包含 Changelog 表
```

#### Step 8: 更新 scripts/verify-init.sh

在现有检查项之后（推荐在"Configuration"检查段之后），新增活文档检查段落：

```bash
# --- Living Documents ---
echo ""
echo "=== Living Documents ==="

for doc in requirement.md design.md test-spec.md implementation.md review.md acceptance.md; do
  if [ -f "docs/$doc" ]; then
    echo "  ✅ docs/$doc"
    ((pass++))
  else
    echo "  ❌ docs/$doc — 缺失"
    ((fail++))
  fi
done
```

新增 6 个检查项（docs/ 下 6 个活文档文件是否存在）。

#### Step 9: Git 提交

```bash
git add docs/requirement.md docs/design.md docs/test-spec.md \
        docs/implementation.md docs/review.md docs/acceptance.md \
        skills/agent-acceptor/SKILL.md skills/agent-designer/SKILL.md \
        skills/agent-tester/SKILL.md skills/agent-implementer/SKILL.md \
        skills/agent-reviewer/SKILL.md skills/agent-init/SKILL.md \
        scripts/verify-init.sh
git commit -m "feat: T-015 project-level living documents system

- Add 6 living doc templates in docs/
- Update 5 agent SKILL.md files with append-after-stage rules
- Update agent-init to create templates during initialization
- Update verify-init.sh to check living doc files

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

## Test Spec (测试规格)

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | `docs/requirement.md` 初始模板存在 | 文件包含 `# 需求文档` 标题和"验收者 (Acceptor)"说明 |
| 2 | `docs/design.md` 初始模板存在 | 文件包含 `# 设计文档` 标题和"设计者 (Designer)"说明 |
| 3 | `docs/test-spec.md` 初始模板存在 | 文件包含 `# 测试规格` 标题和"测试者 (Tester)"说明 |
| 4 | `docs/implementation.md` 初始模板存在 | 文件包含 `# 实现文档` 标题和"实现者 (Implementer)"说明 |
| 5 | `docs/review.md` 初始模板存在 | 文件包含 `# 审查文档` 标题和"审查者 (Reviewer)"说明 |
| 6 | `docs/acceptance.md` 初始模板存在 | 文件包含 `# 验收文档` 标题和"验收者 (Acceptor)"说明 |
| 7 | agent-acceptor SKILL.md 包含活文档追加步骤 | 流程A含 requirement.md 追加步骤，流程B含 acceptance.md 追加步骤 |
| 8 | agent-designer SKILL.md 包含活文档追加步骤 | 流程A含 design.md 追加步骤，流程B含修订记录追加 |
| 9 | agent-tester SKILL.md 包含活文档读取+追加步骤 | 流程A先读取 requirement.md + design.md，再追加 test-spec.md |
| 10 | agent-implementer SKILL.md 包含活文档追加步骤 | 流程A含 implementation.md 追加步骤 |
| 11 | agent-reviewer SKILL.md 包含活文档追加步骤 | 审查流程含 review.md 追加步骤 |
| 12 | agent-init SKILL.md 包含模板创建步骤 | Step 2 后有 docs/ 模板创建步骤，不覆盖已有文件 |
| 13 | verify-init.sh 检查活文档 | 包含 6 个 docs/*.md 文件的存在性检查 |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 14 | Acceptor 发布任务 T-100 后 | docs/requirement.md 末尾新增 `## T-100: <title>` 章节，含功能目标表 |
| 15 | Designer 完成 T-100 设计后 | docs/design.md 末尾新增 `## T-100: <title>` 章节，含文件变更清单 |
| 16 | Tester 生成 T-100 测试用例前 | Tester 读取了 docs/requirement.md 和 docs/design.md 中 T-100 章节 |
| 17 | Tester 生成 T-100 测试用例后 | docs/test-spec.md 末尾新增 `## T-100` 章节，测试矩阵含"覆盖 Goal"列 |
| 18 | Implementer 完成 T-100 实现后 | docs/implementation.md 末尾新增 `## T-100` 章节，含 commit hash |
| 19 | Reviewer 完成 T-100 审查后 | docs/review.md 末尾新增 `## T-100` 章节，含审查结论 |
| 20 | Acceptor 完成 T-100 验收后 | docs/acceptance.md 末尾新增 `## T-100` 章节，含 Goals 验收结果 |
| 21 | 连续完成 T-100 和 T-101 | 每个活文档中包含两个 `## T-NNN` 章节，以 `---` 分隔，顺序正确 |
| 22 | T-100 验收失败后重新设计 | docs/design.md 中 T-100 章节 Changelog 追加修订记录（或新增修订章节） |
| 23 | agent-init 在新项目执行初始化 | docs/ 下创建 6 个活文档初始模板 + 已有 agent-rules.md 不受影响 |
| 24 | agent-init 在已初始化项目重新执行 | docs/ 下已有活文档不被覆盖 |

### 验收标准

- [ ] G1: `docs/` 下存在 6 个活文档模板文件，各自包含标准结构（标题、说明、章节模板）和 Changelog 表
- [ ] G2: 5 个 Agent SKILL.md 均包含"活文档维护规则"章节和流程中的追加步骤
- [ ] G3: 活文档为累积式——每个任务追加 `## T-NNN: title` 新章节，不覆盖已有内容
- [ ] G4: Tester SKILL.md 流程A 在写入 test-spec.md 前先读取 requirement.md + design.md
- [ ] G5: agent-init SKILL.md 在初始化流程中创建 docs/ 活文档模板（不覆盖已有文件）

## Consequences (后果)

### 正面
- **全局视图集中**：打开任一活文档即可纵览所有任务在该阶段的摘要，无需在 `.agents/runtime/` 多层目录间跳转
- **知识累积**：后续任务的 Designer/Tester 可参考前序任务的设计决策和测试策略
- **跨 Agent 信息链路**：Tester 明确从 requirement.md + design.md 获取输入，信息来源可追溯
- **Git 友好**：Markdown 格式在 Git diff 中可读性好，变更历史清晰
- **与现有系统兼容**：活文档是增量新增，不替代 `.agents/runtime/*/workspace/` 中的详细文档

### 负面/风险
- **文件体积增长**：随任务数增加，每个活文档会变长（通过摘要而非全文复制来控制，每章节 30-50 行）
- **写入纪律依赖**：Agent 必须遵守"先追加活文档再转移 FSM"的流程，缺乏硬性约束
- **并发追加冲突**：如果两个 Agent 同时追加同一文件（理论上不会，因为同一时刻只有一个 Agent 活跃），可能导致 Git 冲突

### 后续影响
- 已有任务（T-001 ~ T-014）的活文档章节为空，不追溯补填
- 从 T-015 开始的新任务将开始累积活文档内容
- 未来可考虑：自动生成活文档的 TOC 索引页，或提供 `/docs status` 命令查看各文档的最新章节
- 文件过大时可按年份归档（如 `docs/archive/2024-design.md`）

## 目标覆盖自查

| Goal ID | Goal 描述 | 对应设计章节 | 覆盖状态 |
|---------|----------|-------------|---------|
| G1 | 6 个活文档模板定义 | Template Specs (模板规格) — 6 个模板完整定义 | ✅ 已覆盖 |
| G2 | 5 个 Agent SKILL.md 更新 | Implementation Steps 3-7 — 逐个 Agent 更新说明 | ✅ 已覆盖 |
| G3 | 累积式追加 | Data Model > 累积规则 + 各模板的追加规则 | ✅ 已覆盖 |
| G4 | Tester 读取 requirement + design | Implementation Step 5 + Tester 活文档维护规则 > 读取规则 | ✅ 已覆盖 |
| G5 | agent-init 创建初始模板 | Implementation Step 2 + Architecture > agent-init 初始化时 | ✅ 已覆盖 |

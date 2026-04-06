# T-011: 增强 Implementer 的 TDD 纪律和验证循环

## Context

当前 `agent-implementer SKILL.md` 包含基本的 TDD 流程（Flow A），但缺乏：
1. **严格的 git checkpoint 纪律**：没有要求在 RED/GREEN/REFACTOR 每步做 git 提交，导致代码回滚困难
2. **覆盖率门槛**：没有明确的覆盖率要求，实现者可能写不够测试
3. **增量构建修复流程**：遇到构建错误时缺乏系统化的逐个修复策略
4. **提交前验证清单**：没有在 FSM 转移前强制执行完整的质量检查

借鉴 ECC（Effective Copilot Coding）最佳实践，需要将这些纪律融入 Implementer 工作流。

## Decision

增强 `agent-implementer SKILL.md`，新增三个核心章节：
1. **TDD 严格模式**：RED/GREEN/REFACTOR 每步 git checkpoint + 80% 覆盖率门槛
2. **Build Fix 工作流**：逐个错误修复 + 重新构建 + 进度跟踪
3. **Pre-Review Verification 清单**：5 步质量检查链

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: SKILL.md 增强（选中）** | 无需额外工具，与现有框架一致 | 依赖 Agent 遵守 | ✅ 选中 |
| **B: Hook 强制执行** | 硬性约束 | Hook 是 shell 脚本，无法运行测试/lint | ❌ 技术限制 |
| **C: 外部 CI 集成** | 真正自动化 | 增加外部依赖，超出框架范围 | ❌ 范围溢出 |
| **D: 独立验证 Agent** | 职责分离 | Agent 数量膨胀，流程变长 | ❌ 过度设计 |

## Design

### Architecture

```
Implementer 增强后的工作流：

┌─────────────────────────────────────────────┐
│  Flow A: TDD 严格模式                         │
│  ┌─────┐   ┌─────┐   ┌─────────┐            │
│  │ RED │──→│GREEN│──→│REFACTOR │──→ 循环     │
│  │ 🔴  │   │ 🟢  │   │ 🔵      │            │
│  └──┬──┘   └──┬──┘   └────┬────┘            │
│     │git      │git        │git              │
│     │commit   │commit     │commit           │
│     ▼         ▼           ▼                 │
│  checkpoint  checkpoint  checkpoint          │
│                                              │
│  覆盖率 >= 80%? ──否──→ 补充测试 ──→ 循环      │
│       │是                                    │
│       ▼                                      │
│  ┌──────────────────────────────────────┐    │
│  │  Pre-Review Verification             │    │
│  │  typecheck → build → lint → test     │    │
│  │  → security scan                     │    │
│  │  全部 ✅ → FSM: implementing→reviewing│    │
│  └──────────────────────────────────────┘    │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Build Fix 工作流（构建失败时）                  │
│  ┌──────┐   ┌──────────┐   ┌─────────┐      │
│  │读取错误│──→│修复第1个  │──→│重新构建   │     │
│  │列表   │   │错误      │   │         │      │
│  └──────┘   └──────────┘   └────┬────┘      │
│                                  │           │
│                    还有错误? ──是──→ 循环      │
│                         │否                  │
│                         ▼                    │
│                    构建成功 ✅                 │
└─────────────────────────────────────────────┘
```

### API / Interface

**agent-implementer SKILL.md 新增章节**：

#### 1. TDD 严格模式

```markdown
### TDD 严格模式

#### RED 阶段 🔴
1. 根据设计文档编写**失败的测试**
2. 运行测试，确认测试失败（预期失败）
3. `git add -A && git commit -m "test: RED - <测试描述>"`

#### GREEN 阶段 🟢
1. 编写**最少量的代码**使测试通过
2. 运行测试，确认全部通过
3. `git add -A && git commit -m "feat: GREEN - <功能描述>"`

#### REFACTOR 阶段 🔵
1. 优化代码结构，消除重复
2. 运行测试，确认仍全部通过
3. `git add -A && git commit -m "refactor: REFACTOR - <重构描述>"`

#### 覆盖率门槛
- 目标：**80% 以上**行覆盖率
- 检查方式：运行测试覆盖率工具（jest --coverage / pytest --cov / go test -cover）
- 未达标时：补充测试用例，重复 RED-GREEN 循环
- 覆盖率报告保存到 `.agents/runtime/implementer/workspace/coverage-report.txt`
```

#### 2. Build Fix 工作流

```markdown
### Build Fix 工作流

当构建/编译失败时，执行以下流程：

1. **收集错误**：运行构建命令，捕获所有错误输出
2. **错误排序**：按文件和行号排序，从第一个开始
3. **逐个修复**：
   - 只修复当前第一个错误
   - 修复后立即重新构建
   - 记录: `错误 N/M 已修复`
4. **循环直到成功**：重复步骤 3 直到构建通过
5. **进度跟踪**：在 stderr 输出进度 `[BUILD FIX] 3/7 errors fixed`

⚠️ 禁止一次修复多个不相关错误——逐个修复可避免引入新问题。
```

#### 3. Pre-Review Verification 清单

```markdown
### Pre-Review Verification 清单

在将任务状态从 `implementing` 转移到 `reviewing` 之前，**必须**按顺序通过以下 5 项检查：

| # | 检查项 | 命令示例 | 通过标准 |
|---|--------|---------|---------|
| 1 | 类型检查 | `tsc --noEmit` / `mypy` | 0 errors |
| 2 | 构建 | `npm run build` / `go build` | exit 0 |
| 3 | Lint | `eslint .` / `flake8` | 0 errors (warnings OK) |
| 4 | 测试 | `npm test` / `pytest` | 全部通过 + 覆盖率 >= 80% |
| 5 | 安全扫描 | `npm audit` / `pip audit` | 无 HIGH/CRITICAL |

任何一项未通过，**禁止**转移 FSM 状态。修复后重新运行对应检查。

验证结果记录到 `.agents/runtime/implementer/workspace/verification-report.md`：
```

**验证报告模板**：

```markdown
# Pre-Review Verification Report — T-NNN

| 检查项 | 状态 | 详情 |
|--------|------|------|
| 类型检查 | ✅ | 0 errors |
| 构建 | ✅ | Build succeeded in 12s |
| Lint | ✅ | 0 errors, 3 warnings |
| 测试 | ✅ | 47/47 passed, 83% coverage |
| 安全扫描 | ✅ | No vulnerabilities found |

**结论**: 全部通过，可以转移到 reviewing 阶段。
```

### Implementation Steps

1. **更新 `skills/agent-implementer/SKILL.md`**：
   - 在现有 "Flow A: 新功能实现" 之后，新增"TDD 严格模式"章节
   - 定义 RED/GREEN/REFACTOR 三阶段的具体步骤和 git commit 格式
   - 定义 80% 覆盖率门槛和检查方法

2. **新增"Build Fix 工作流"章节**：
   - 在 SKILL.md 中现有流程之后添加
   - 定义逐个修复策略、进度跟踪格式
   - 强调"一次只修一个错误"原则

3. **新增"Pre-Review Verification 清单"章节**：
   - 定义 5 步检查链（typecheck → build → lint → test → security）
   - 提供各语言/框架的命令示例
   - 定义验证报告模板和存放路径

4. **更新现有 Flow A 和 Flow B**：
   - Flow A 中引用"TDD 严格模式"章节
   - Flow B（Bug 修复）中引用"Build Fix 工作流"
   - 两个 Flow 在最后一步都引用"Pre-Review Verification"

5. **定义验证报告存放位置**：
   - 路径：`.agents/runtime/implementer/workspace/verification-report.md`
   - 覆盖率报告：`.agents/runtime/implementer/workspace/coverage-report.txt`

6. **更新 FSM Guard 规则**：
   - 在 `skills/agent-fsm/SKILL.md` 的 guard 规则中补充：
     `implementing → reviewing` 需要 verification report 存在且全部 ✅

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | SKILL.md 包含"TDD 严格模式"章节 | 章节存在且包含 RED/GREEN/REFACTOR 步骤 |
| 2 | SKILL.md 包含"Build Fix 工作流"章节 | 章节存在且包含逐个修复流程 |
| 3 | SKILL.md 包含"Pre-Review Verification"章节 | 章节存在且包含 5 项检查 |
| 4 | git commit 格式定义 | 包含 `test: RED -`, `feat: GREEN -`, `refactor: REFACTOR -` 模板 |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 5 | Implementer 执行完整 TDD 循环 | 产出 RED/GREEN/REFACTOR 三次 git commit |
| 6 | 构建失败后执行 Build Fix | 逐个修复，每次修复后重新构建 |
| 7 | Pre-Review 验证失败 | 禁止转移到 reviewing，修复后重试 |
| 8 | 覆盖率 < 80% | 阻止提交，提示补充测试 |

### 验收标准

- [ ] G1: TDD 章节包含 RED/GREEN/REFACTOR git checkpoint + 80% 覆盖率门槛
- [ ] G2: Build Fix 工作流包含逐个修复 + 重新构建 + 进度跟踪
- [ ] G3: Pre-Review Verification 包含 typecheck → build → lint → test → security scan 五步检查

## Consequences

**正面**：
- 代码质量显著提升，有完整的质量门控
- Git 历史清晰，每步可追溯、可回滚
- 构建问题系统化解决，避免混乱修复

**负面/风险**：
- TDD 严格模式增加开发时间（但减少后期修复时间）
- 覆盖率门槛可能对某些项目过高（但 80% 是业界共识）
- 需要 Implementer Agent 严格遵守流程

**后续影响**：
- T-012 Reviewer 增强可以检查是否遵守了 TDD 纪律（查看 git log）
- T-013 Tester 增强可以利用覆盖率报告

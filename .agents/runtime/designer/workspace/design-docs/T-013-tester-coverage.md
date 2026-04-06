# T-013: 增强 Tester 的覆盖率分析和 Flaky 检测

## Context

当前 `agent-tester SKILL.md` 定义了完整的测试流程（Flow A/B）和 issue 跟踪机制，但缺乏：
1. **覆盖率分析**：没有系统化的覆盖率检测、解析和高优先级未覆盖区域识别
2. **Flaky 测试检测**：间歇性失败的测试会导致 CI 不稳定，当前没有检测和隔离机制
3. **E2E 测试指导**：缺少端到端测试的最佳实践，如 Page Object Model、Playwright 集成

## Decision

增强 `agent-tester SKILL.md`，新增三个核心章节：覆盖率分析工作流 + Flaky 检测与隔离 + E2E 测试最佳实践。

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: SKILL.md 增强（选中）** | 框架一致，语言无关 | 依赖 Agent 遵守 | ✅ 选中 |
| **B: 集成 Codecov/Coveralls** | 自动化覆盖率追踪 | 需要外部服务和 CI | ❌ 外部依赖 |
| **C: 自定义覆盖率脚本** | 精确控制 | 每种语言需要单独实现 | ❌ 维护成本 |
| **D: 仅在 Implementer 中处理** | 减少 Tester 负担 | 职责不清，Tester 应验证质量 | ❌ 职责错位 |

## Design

### Architecture

```
Tester 增强后的工作流：

┌─────────────────────────────────────────────┐
│  现有 Flow A: 新任务测试                      │
│  ...                                         │
│  新增步骤: 覆盖率分析                          │
│  ┌────────────────────────────────────┐       │
│  │ 检测测试框架                         │      │
│  │    ▼                               │       │
│  │ 运行覆盖率命令                       │      │
│  │    ▼                               │       │
│  │ 解析覆盖率报告                       │      │
│  │    ▼                               │       │
│  │ 识别高优先级未覆盖区域                │      │
│  │    ▼                               │       │
│  │ 输出覆盖率摘要                       │      │
│  └────────────────────────────────────┘       │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Flaky 检测流程                               │
│  ┌────────────────────────────────────┐       │
│  │ 测试失败?                           │      │
│  │    │是                             │       │
│  │    ▼                               │       │
│  │ 重新运行 3-5 次                     │       │
│  │    ▼                               │       │
│  │ 结果不一致? ──是──→ 标记为 Flaky     │      │
│  │    │否                ▼            │       │
│  │    ▼            test.fixme() 隔离   │      │
│  │ 确认为真实失败                       │      │
│  │    ▼                               │       │
│  │ 报告 issue                         │       │
│  └────────────────────────────────────┘       │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  E2E 测试最佳实践                             │
│  ├── Page Object Model 模式                  │
│  ├── data-testid 选择器策略                    │
│  ├── Playwright 推荐配置                      │
│  └── 失败时截图/视频                           │
└─────────────────────────────────────────────┘
```

### Data Model

**覆盖率报告格式**：

```json
{
  "task_id": "T-013",
  "timestamp": "2026-04-06T16:00:00Z",
  "framework": "jest",
  "overall": {
    "lines": 83.2,
    "branches": 76.5,
    "functions": 88.1,
    "statements": 82.9
  },
  "uncovered_critical": [
    {
      "file": "src/hooks/agent-post-tool-use.ts",
      "lines": "45-62",
      "reason": "auto-dispatch 逻辑分支未覆盖"
    }
  ]
}
```

**Flaky 测试记录格式**：

```json
{
  "test_name": "should auto-dispatch on status change",
  "file": "tests/hooks.test.ts:42",
  "runs": [
    {"run": 1, "result": "FAIL", "duration_ms": 1200},
    {"run": 2, "result": "PASS", "duration_ms": 980},
    {"run": 3, "result": "FAIL", "duration_ms": 1150},
    {"run": 4, "result": "PASS", "duration_ms": 1020},
    {"run": 5, "result": "PASS", "duration_ms": 990}
  ],
  "pass_rate": "60%",
  "verdict": "FLAKY",
  "action": "quarantine with test.fixme()",
  "quarantined_at": "2026-04-06T16:30:00Z"
}
```

### API / Interface

**agent-tester SKILL.md 新增章节**：

#### 1. 覆盖率分析工作流

```markdown
### 覆盖率分析工作流

在测试执行后，执行覆盖率分析：

#### Step 1: 检测测试框架
自动识别项目使用的测试框架和覆盖率工具：
| 框架 | 覆盖率命令 | 报告格式 |
|------|-----------|---------|
| Jest | `npx jest --coverage --coverageReporters=text` | 终端文本 |
| Vitest | `npx vitest run --coverage` | 终端文本 |
| pytest | `pytest --cov=src --cov-report=term-missing` | 终端文本 |
| Go | `go test -cover -coverprofile=coverage.out ./...` | 文本 |

#### Step 2: 运行覆盖率
执行上表对应的命令，捕获输出。

#### Step 3: 解析报告
提取关键指标：行覆盖率、分支覆盖率、函数覆盖率。

#### Step 4: 识别高优先级未覆盖区域
优先级排序：
1. 本次修改的文件（files_modified）中未覆盖的行 — 最高优先
2. 核心业务逻辑文件中的未覆盖分支
3. 错误处理路径（catch/error/reject）

#### Step 5: 输出摘要
将覆盖率摘要写入测试报告，若低于 80% 则标记为需关注。
```

#### 2. Flaky 测试检测与隔离

```markdown
### Flaky 测试检测与隔离

当测试失败时，先判断是否为 Flaky（间歇性失败）：

#### 检测流程
1. 测试失败 → 不立即报告 issue
2. 重新运行该测试 3-5 次（使用 `--bail` 或单独运行）
3. 统计通过率：
   - 通过率 100% → 原始失败为偶发，标记为疑似 Flaky，继续观察
   - 通过率 0% → 确认为真实失败，报告 issue
   - 通过率 1-99% → 确认为 Flaky

#### 隔离操作
确认为 Flaky 的测试：
1. 标记为 `test.fixme()` / `test.skip()` + 注释说明
2. 创建 Flaky issue 到 `T-NNN-issues.json`，severity 为 MEDIUM
3. 记录 Flaky 详情到 `.agents/runtime/tester/workspace/flaky-tests.json`

#### 根因分析提示
常见 Flaky 根因：
- 时间依赖（setTimeout, Date.now）
- 网络依赖（外部 API 调用）
- 状态泄漏（测试间共享状态）
- 竞态条件（异步操作顺序不确定）
```

#### 3. E2E 测试最佳实践

```markdown
### E2E 测试最佳实践

对于 Web 应用的端到端测试，遵循以下实践：

#### Page Object Model (POM)
每个页面创建对应的 Page Object 类：
```typescript
// pages/LoginPage.ts
export class LoginPage {
  constructor(private page: Page) {}
  
  async login(username: string, password: string) {
    await this.page.getByTestId('username').fill(username);
    await this.page.getByTestId('password').fill(password);
    await this.page.getByTestId('login-btn').click();
  }
}
```

#### 选择器策略
优先级（从高到低）：
1. `data-testid` — 最稳定，不受 UI 变化影响
2. `role` + `name` — 语义化，支持无障碍
3. `text` — 用户可见文本
4. ❌ 避免: CSS class、XPath、DOM 结构

#### Playwright 推荐配置
```typescript
// playwright.config.ts
export default defineConfig({
  retries: 2,
  use: {
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    trace: 'on-first-retry',
  },
});
```

#### 失败时证据收集
测试失败时自动收集：
- 截图（screenshot）
- 视频录制（video）
- 网络日志（HAR）
- 控制台日志（console log）
保存到 `.agents/runtime/tester/workspace/e2e-artifacts/`
```

### Implementation Steps

1. **更新 `skills/agent-tester/SKILL.md` — 覆盖率分析章节**：
   - 在现有 Flow A 流程末尾新增"覆盖率分析"步骤
   - 定义 4 种主流测试框架的覆盖率命令
   - 定义高优先级未覆盖区域的识别规则
   - 定义覆盖率摘要输出格式

2. **新增 Flaky 测试检测章节**：
   - 定义检测流程：失败 → 重跑 3-5 次 → 判定
   - 定义通过率阈值和对应动作
   - 定义隔离操作（test.fixme + issue + 记录文件）
   - 列出常见 Flaky 根因

3. **新增 E2E 测试最佳实践章节**：
   - 定义 Page Object Model 模式和代码示例
   - 定义选择器优先级策略
   - 提供 Playwright 推荐配置
   - 定义失败时证据收集规则

4. **定义输出文件路径**：
   - 覆盖率报告：`.agents/runtime/tester/workspace/coverage-summary.json`
   - Flaky 记录：`.agents/runtime/tester/workspace/flaky-tests.json`
   - E2E 证据：`.agents/runtime/tester/workspace/e2e-artifacts/`

5. **更新现有 Flow A 流程**：
   - 在"运行测试"步骤后，增加"覆盖率分析"子步骤
   - 在"报告 issue"步骤前，增加"Flaky 检测"判断
   - 在测试报告模板中增加覆盖率摘要和 Flaky 统计

6. **更新测试报告模板**：
   - 新增"覆盖率摘要"分节
   - 新增"Flaky 测试"分节
   - 新增"E2E 测试结果"分节（含截图链接）

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | SKILL.md 包含覆盖率分析章节 | 4 种框架覆盖率命令均存在 |
| 2 | SKILL.md 包含 Flaky 检测章节 | 重跑次数和判定阈值明确 |
| 3 | SKILL.md 包含 E2E 章节 | POM 模式、选择器策略、Playwright 配置均存在 |
| 4 | Flaky 记录格式定义 | JSON 格式包含 runs, pass_rate, verdict |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 5 | 测试失败后重跑 3 次，2 次通过 | 标记为 Flaky，隔离到 test.fixme() |
| 6 | 测试失败后重跑 3 次，0 次通过 | 确认为真实失败，报告 issue |
| 7 | 覆盖率 < 80% | 测试报告标注"需关注"，列出未覆盖区域 |
| 8 | E2E 测试失败 | 自动收集截图和视频到 e2e-artifacts/ |

### 验收标准

- [ ] G1: 覆盖率分析工作流包含框架检测、运行、解析、高优区域识别
- [ ] G2: Flaky 检测包含 3-5 次重跑、通过率判定、test.fixme() 隔离
- [ ] G3: E2E 章节包含 POM 模式、data-testid 策略、Playwright 配置、失败截图

## Consequences

**正面**：
- 覆盖率可量化追踪，高优先级盲区优先补充测试
- Flaky 测试不再阻塞 CI 流水线，但仍被跟踪修复
- E2E 测试有标准化实践，新 Agent 可快速上手

**负面/风险**：
- 覆盖率命令因项目配置不同可能需要调整
- Flaky 重跑 3-5 次增加测试时间
- POM 模式增加初始编写成本（但减少维护成本）

**后续影响**：
- T-011 Implementer 的覆盖率门槛可与 Tester 的覆盖率分析协同
- Flaky 记录可用于项目级质量分析

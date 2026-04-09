---
name: agent-docs
description: "文档流水线 — 标准化阶段性文档模板、输入/输出矩阵、FSM 文档门禁"
---

# Agent Document Pipeline

> 每个 SDLC 阶段必须产出标准化文档，作为下一阶段的输入。文档是 Agent 间协作的正式交付物。

## 文档流转矩阵

| 阶段 | Agent | 输入文档 | 输出文档 |
|------|-------|---------|---------|
| 需求定义 | Acceptor | (用户需求) | `requirements.md` + `acceptance-criteria.md` |
| 架构设计 | Designer | requirements.md | `design.md` |
| 编码实现 | Implementer | requirements.md + design.md | `implementation.md` |
| 代码审查 | Reviewer | requirements.md + design.md + implementation.md | `review-report.md` |
| 测试验证 | Tester | requirements.md + design.md + implementation.md | `test-report.md` |
| 验收 | Acceptor | acceptance-criteria.md + 全部文档 | Accept / Reject |

## 文档存储

所有文档按任务 ID 存放：

```
.agents/docs/T-XXX/
  requirements.md          ← Acceptor 产出
  acceptance-criteria.md   ← Acceptor 产出
  design.md                ← Designer 产出
  implementation.md        ← Implementer 产出
  review-report.md         ← Reviewer 产出
  test-report.md           ← Tester 产出
```

## Agent 启动流程

切换到任何 Agent 时，**必须**：

1. 确认当前任务 ID（从 task-board 读取）
2. 检查 `.agents/docs/T-XXX/` 下的输入文档是否存在
3. 如果输入文档存在 → **先阅读全部输入文档**，再开始工作
4. 如果输入文档缺失 → 提醒用户需先完成前序阶段
5. 工作完成后，**必须**创建本阶段的输出文档

## FSM 过渡文档门禁

状态转换前，检查当前阶段的输出文档是否已创建：

| 转换 | 必须存在的文档 |
|------|--------------|
| `created → designing` | `requirements.md` + `acceptance-criteria.md` |
| `designing → implementing` | `design.md` |
| `implementing → reviewing` | `implementation.md` |
| `reviewing → testing` | `review-report.md` |
| `testing → accepting` | `test-report.md` |
| `accepting → accepted` | (验收者确认所有目标通过) |
| `reviewing → implementing` (打回) | `review-report.md`（含问题列表）|
| `testing → fixing` (发现问题) | `test-report.md`（含失败用例）|

> **门禁模式** 由 `task-board.json` 顶层字段 `"doc_gate_mode"` 控制：
>
> | 模式 | 行为 |
> |------|------|
> | `"warn"` (默认) | ⚠️ 输出警告，不阻止转换。AI Agent 应自动补齐 |
> | `"strict"` | ⛔ 阻止转换，`LEGAL=false`。必须先写好文档才能推进 |
>
> 配置方法：在 `task-board.json` 中添加 `"doc_gate_mode": "strict"`

---

## 文档模板

### 1. 需求文档 (`requirements.md`)

```markdown
# 需求文档: T-XXX — {任务标题}

## 1. 背景与目标
{为什么需要这个功能/修复，解决什么问题}

## 2. 功能需求
### 2.1 核心功能
- [ ] {功能点 1}
- [ ] {功能点 2}

### 2.2 约束条件
- {技术约束、兼容性要求、性能要求等}

## 3. 非功能需求
- **性能**: {响应时间、吞吐量等}
- **安全**: {权限、数据保护等}
- **兼容性**: {平台、浏览器、API 版本等}

## 4. 范围
### 包含
- {明确包含的功能}

### 不包含
- {明确排除的功能}

## 5. 依赖
- {外部依赖、前置条件}

---
*由 Acceptor 创建于 {日期}*
```

### 2. 验收标准文档 (`acceptance-criteria.md`)

```markdown
# 验收标准: T-XXX — {任务标题}

## 验收条件

### AC-1: {验收条件标题}
- **给定**: {前置条件}
- **当**: {操作步骤}
- **那么**: {预期结果}

### AC-2: {验收条件标题}
- **给定**: {前置条件}
- **当**: {操作步骤}
- **那么**: {预期结果}

## 验收方式
- [ ] 功能验证: {如何验证功能正确}
- [ ] 边界测试: {极端情况测试}
- [ ] 回归确认: {不影响现有功能}

## 不接受条件
- {明确不接受的情况，如崩溃、数据丢失等}

---
*由 Acceptor 创建于 {日期}*
```

### 3. 设计文档 (`design.md`)

```markdown
# 设计文档: T-XXX — {任务标题}

## 1. 需求分析
{对 requirements.md 的理解和补充分析}

## 2. 技术方案

### 2.1 架构设计
{整体架构、模块划分、数据流}

### 2.2 接口设计
{API 接口、函数签名、数据结构}

### 2.3 数据模型
{数据库表、JSON 结构等}

## 3. 实现策略
- **方案选择**: {选择了什么方案，为什么}
- **备选方案**: {考虑过但放弃的方案，原因}

## 4. 影响范围
- **新增文件**: {列出要新增的文件}
- **修改文件**: {列出要修改的文件}
- **风险点**: {可能的风险和缓解措施}

## 5. 测试建议
- {建议的测试用例方向}
- {需要覆盖的边界情况}

---
*由 Designer 创建于 {日期} | 基于 requirements.md*
```

### 4. 实现文档 (`implementation.md`)

```markdown
# 实现文档: T-XXX — {任务标题}

## 1. 实现概述
{实现了什么，采用了什么方法}

## 2. 变更列表

### 新增文件
| 文件 | 用途 |
|------|------|
| {path} | {说明} |

### 修改文件
| 文件 | 变更内容 |
|------|---------|
| {path} | {说明} |

## 3. 关键实现细节
{核心逻辑、算法、设计模式等}

## 4. 与设计文档的偏差
{如果有与 design.md 不一致的地方，说明原因}

## 5. 测试覆盖
- **单元测试**: {新增/修改的测试文件}
- **自测结果**: {本地运行结果}

## 6. 已知限制
- {目前已知的限制或待优化项}

---
*由 Implementer 创建于 {日期} | 基于 design.md + requirements.md*
```

### 5. 审查报告 (`review-report.md`)

```markdown
# 审查报告: T-XXX — {任务标题}

## 1. 审查范围
- **审查文件数**: {N}
- **审查基于**: requirements.md + design.md + implementation.md

## 2. 审查结论: {✅ 通过 / ❌ 打回 / ⚠️ 有条件通过}

## 3. 问题列表

### 🔴 必须修复 (Blockers)
| # | 文件 | 行号 | 问题 | 严重性 |
|---|------|------|------|--------|
| 1 | {path} | {line} | {描述} | HIGH |

### 🟡 建议修复 (Suggestions)
| # | 文件 | 行号 | 问题 | 严重性 |
|---|------|------|------|--------|
| 1 | {path} | {line} | {描述} | MEDIUM |

### 🟢 可选优化 (Nice-to-have)
- {建议}

## 4. 质量评估
- **代码质量**: ⭐⭐⭐⭐☆
- **测试覆盖**: ⭐⭐⭐⭐☆
- **设计符合度**: ⭐⭐⭐⭐☆
- **安全性**: ⭐⭐⭐⭐⭐

## 5. 与设计文档一致性
{实现是否符合 design.md 的设计方案}

---
*由 Reviewer 创建于 {日期} | 基于 requirements.md + design.md + implementation.md*
```

### 6. 测试报告 (`test-report.md`)

```markdown
# 测试报告: T-XXX — {任务标题}

## 1. 测试范围
- **测试基于**: requirements.md + design.md + implementation.md
- **验收标准参考**: acceptance-criteria.md

## 2. 测试结论: {✅ 全部通过 / ❌ 有失败 / ⚠️ 部分通过}

## 3. 测试用例结果

| # | 用例名称 | 类型 | 预期结果 | 实际结果 | 状态 |
|---|---------|------|---------|---------|------|
| 1 | {名称} | 功能/边界/异常 | {预期} | {实际} | ✅/❌ |

## 4. 失败用例详情
### TC-{N}: {用例名称}
- **复现步骤**: {步骤}
- **预期**: {预期结果}
- **实际**: {实际结果}
- **截图/日志**: {如有}

## 5. 覆盖率
- **需求覆盖**: {X}/{Y} 个需求点已测试
- **验收条件覆盖**: {X}/{Y} 个 AC 已验证
- **代码覆盖**: {如有覆盖率数据}

## 6. 风险评估
- {未覆盖的测试点}
- {发现的非阻塞问题}

---
*由 Tester 创建于 {日期} | 基于 requirements.md + design.md + implementation.md*
```

---

## 3-Phase 模式扩展

3-Phase 模式下，文档更加细化：

| 阶段 | 输出文档 |
|------|---------|
| requirements | `requirements.md` + `acceptance-criteria.md` |
| architecture | `design.md` (§2.1 架构部分) |
| tdd_design | `design.md` (§5 测试建议 → 完整测试设计) |
| dfmea | `design.md` (附录: DFMEA 风险分析) |
| design_review | `review-report.md` (设计审查版) |
| implementing | `implementation.md` |
| code_reviewing | `review-report.md` (代码审查版) |
| ci_monitoring | `test-report.md` (CI 报告部分) |
| device_baseline | `test-report.md` (设备基线部分) |
| regression_testing | `test-report.md` (回归测试部分) |
| feature_testing | `test-report.md` (功能测试部分) |
| log_analysis | `test-report.md` (日志分析部分) |
| documentation | `implementation.md` (更新最终版本) |

---

## 命令支持

AI Agent 可以使用以下命令管理文档：

```bash
# 列出任务的所有文档
ls .agents/docs/T-XXX/

# 检查文档完整性
for doc in requirements.md acceptance-criteria.md design.md implementation.md review-report.md test-report.md; do
  [ -f ".agents/docs/T-XXX/$doc" ] && echo "✅ $doc" || echo "❌ $doc (missing)"
done
```

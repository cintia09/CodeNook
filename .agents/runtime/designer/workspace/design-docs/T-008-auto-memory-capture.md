# T-008: 阶段转换时自动捕获记忆

## Context

当前多 Agent 框架中，记忆保存需要 Agent 手动调用 `agent-memory` skill 的"保存记忆"操作。这导致两个问题：
1. Agent 经常忘记保存记忆，导致关键上下文在交接时丢失
2. 手动保存的记忆质量参差不齐，缺少标准化的结构

FSM 状态转移（如 designing → implementing）是天然的记忆保存触发点——此时 Agent 已完成本阶段工作，所有关键信息都在上下文中。

## Decision

在 `agent-post-tool-use.sh` hook 中增加 FSM 状态转移检测逻辑：当检测到 `task-board.json` 中任务状态发生变化时，自动触发记忆快照保存。记忆内容从当前 Agent 上下文中自动提取，写入标准化的 `T-NNN-memory.json` 格式。

## Alternatives Considered

| 方案 | 优点 | 缺点 | 决定 |
|------|------|------|------|
| **A: Hook 检测 + 自动保存（选中）** | 完全自动，无需 Agent 配合 | Hook 脚本复杂度增加 | ✅ 选中 |
| **B: 在 SKILL.md 中强制要求手动保存** | 实现简单 | 依赖 Agent 遵守，容易遗漏 | ❌ 不可靠 |
| **C: 定时自动保存** | 不依赖状态转移 | 可能保存无意义的中间状态，浪费存储 | ❌ 粒度不对 |
| **D: Agent-switch 切换时保存** | 时机明确 | 只覆盖切换场景，不覆盖同 Agent 内状态变化 | ❌ 覆盖不全 |

## Design

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  Agent 执行工具（edit/bash/write）                      │
└──────────────────────┬──────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────┐
│  agent-post-tool-use.sh                             │
│  ├── 现有: 记录 events.db                             │
│  ├── 现有: AUTO-DISPATCH (检测状态变化→发消息)           │
│  └── 新增: AUTO-MEMORY-CAPTURE                       │
│       ├── 比较 task-board.json 前后状态                │
│       ├── 若状态变化 → 生成记忆提取指令                  │
│       └── 写入 .agents/memory/T-NNN-memory.json       │
└─────────────────────────────────────────────────────┘
```

**触发机制**：
1. `agent-post-tool-use.sh` 已有检测 `task-board.json` 写入的逻辑（用于 AUTO-DISPATCH）
2. 在同一检测点增加：检测到状态字段变化时，输出记忆捕获指令

**记忆提取策略**：
- Hook 脚本无法直接访问 Agent 上下文（它是 shell 脚本）
- 方案：Hook 输出一个 JSON 指令到 stdout，Copilot 框架读取后执行记忆提取
- 或：在 `agent-memory SKILL.md` 中定义"自动捕获"触发约定，让 Agent 在执行状态转移后立即提取记忆

**实际可行方案**：由于 hook 是 shell 脚本，无法直接操作 LLM 上下文，采用**混合方案**：
1. Hook 检测状态变化，在 `events.db` 中记录 `memory_capture_needed` 事件
2. Hook 的 stdout 返回提示信息，告知 Agent "请立即保存记忆"
3. `agent-memory SKILL.md` 增加"自动捕获"章节，定义标准化提取模板
4. Agent 按模板提取并保存——整个过程对用户透明，无需手动调用

### Data Model

**记忆快照格式**（扩展现有 `T-NNN-memory.json`）：

```json
{
  "task_id": "T-008",
  "version": 2,
  "auto_captured": true,
  "capture_trigger": "designing → implementing",
  "captured_at": "2026-04-06T15:00:00Z",
  "captured_by": "designer",
  "stages": {
    "designing": {
      "summary": "设计了自动记忆捕获机制...",
      "decisions": [
        "采用 hook 检测 + Agent 提取的混合方案",
        "记忆格式兼容现有 T-NNN-memory.json"
      ],
      "artifacts": [
        ".agents/runtime/designer/workspace/design-docs/T-008-auto-memory-capture.md"
      ],
      "files_modified": [
        "hooks/agent-post-tool-use.sh",
        "skills/agent-memory/SKILL.md"
      ],
      "issues_encountered": [
        "Hook 是 shell 脚本，无法直接访问 LLM 上下文"
      ],
      "handoff_notes": "实现者需先修改 hook 脚本，再更新 SKILL.md"
    }
  }
}
```

**events.db 新事件类型**：
```sql
INSERT INTO events (type, agent, task_id, detail, timestamp)
VALUES ('memory_capture_needed', 'designer', 'T-008', 
        '{"from_status":"designing","to_status":"implementing"}', 
        datetime('now'));
```

### API / Interface

**Hook 输出（新增）**：

当检测到状态变化时，hook 在 stderr 输出提示：
```
[AUTO-MEMORY] Task T-008 状态变化: designing → implementing
[AUTO-MEMORY] 请按 agent-memory SKILL.md "自动捕获" 模板保存记忆
```

**agent-memory SKILL.md 新增章节**：

```markdown
### 自动捕获（Auto-Capture）

当你完成阶段工作并转移 FSM 状态后，**必须立即**执行以下记忆保存：

#### 提取模板
从当前工作上下文中提取以下字段：
- **summary**: 一句话总结本阶段完成的工作
- **decisions**: 本阶段做出的关键技术决策（列表）
- **artifacts**: 本阶段产出的文件路径（列表）
- **files_modified**: 本阶段修改的文件路径（列表）
- **issues_encountered**: 遇到的问题和解决方案（列表）
- **handoff_notes**: 给下游 Agent 的交接要点

#### 保存操作
将提取的内容写入 `.agents/memory/T-NNN-memory.json`，设置 `auto_captured: true`。
```

### Implementation Steps

1. **修改 `hooks/agent-post-tool-use.sh`**：
   - 在现有的 `task-board.json` 写入检测逻辑中（约第 40-60 行），增加状态变化前后对比
   - 当检测到 `status` 字段变化时，记录 `memory_capture_needed` 事件到 `events.db`
   - 输出 `[AUTO-MEMORY]` 提示到 stderr

2. **创建记忆目录**：
   - 确保 `.agents/memory/` 目录存在（若不存在则创建）

3. **更新 `skills/agent-memory/SKILL.md`**：
   - 在现有操作列表后新增"自动捕获（Auto-Capture）"章节
   - 包含提取模板（6 个字段）
   - 包含保存操作说明
   - 明确说明：状态转移后 Agent 必须自动执行此操作，无需用户触发

4. **在 hook 中缓存上一次 task-board.json 状态**：
   - Hook 执行时读取当前 `task-board.json`，与上次缓存对比
   - 缓存存放位置：`.agents/runtime/.task-board-cache.json`
   - 首次运行时无缓存，跳过检测

5. **验证 auto-dispatch 与 auto-memory 的兼容性**：
   - 两者都在状态变化时触发，确保执行顺序正确
   - 先 auto-memory（保存当前 Agent 记忆），再 auto-dispatch（通知下游 Agent）

6. **更新 `.gitignore`**：
   - 添加 `.agents/runtime/.task-board-cache.json`（临时缓存不入库）

## Test Spec

### 单元测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 1 | 修改 task-board.json 中任务状态从 designing → implementing | Hook 输出 `[AUTO-MEMORY]` 提示，events.db 记录 `memory_capture_needed` |
| 2 | 修改 task-board.json 中非状态字段（如 priority） | 不触发 auto-memory |
| 3 | 首次运行（无缓存文件） | 不触发 auto-memory，创建缓存 |
| 4 | 同一状态不变的写入（如 implementing → implementing） | 不触发 auto-memory |

### 集成测试

| # | 测试场景 | 预期结果 |
|---|---------|---------|
| 5 | 完整流程：Agent 完成设计 → 更新状态 → 自动保存记忆 | `.agents/memory/T-NNN-memory.json` 包含 `auto_captured: true` |
| 6 | Auto-memory + Auto-dispatch 同时触发 | 先保存记忆，再发送 dispatch 消息，无冲突 |
| 7 | agent-memory SKILL.md 格式验证 | 包含"自动捕获"章节，模板包含 6 个必填字段 |

### 验收标准

- [ ] G1: Hook 检测到 FSM 状态转移并触发记忆保存
- [ ] G2: 记忆快照包含 summary, decisions, files_modified, issues_encountered, handoff_notes
- [ ] G3: agent-memory SKILL.md 包含"自动捕获"章节
- [ ] G4: 全程无需手动调用"保存记忆"

## Consequences

**正面**：
- Agent 交接时永远有上下文可用，不再丢失关键信息
- 记忆格式标准化，下游 Agent 可靠解析
- 与现有 auto-dispatch 机制协同，形成完整的自动化交接流程

**负面/风险**：
- Hook 脚本复杂度增加，需要维护缓存文件
- 记忆提取依赖 Agent 遵守 SKILL.md 约定（但比之前纯手动好得多）
- 缓存文件需要加入 `.gitignore`

**后续影响**：
- T-009（智能记忆加载）直接依赖本任务产出的标准化记忆格式

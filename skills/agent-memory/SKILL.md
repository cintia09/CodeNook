---
name: agent-memory
description: "任务记忆管理: 每个阶段完成后自动保存上下文快照。调用时说 '保存记忆'、'查看记忆'、'任务上下文'。"
---

# 任务记忆管理

## 文件位置
- 记忆文件: `<project>/.agents/memory/T-NNN-memory.json`
- 每个任务一个文件, 跨阶段积累上下文

## T-NNN-memory.json 格式

```json
{
  "task_id": "T-001",
  "version": 1,
  "last_updated": "2026-04-05T12:00:00Z",
  "stages": {
    "designing": {
      "agent": "designer",
      "started_at": "2026-04-05T08:30:00Z",
      "completed_at": "2026-04-05T10:00:00Z",
      "summary": "设计了基于 JWT 的用户认证系统, 采用无状态架构...",
      "decisions": ["选择 JWT 而非 session, 原因: 需支持移动端", "密码哈希使用 bcrypt, cost factor = 12"],
      "artifacts": [".agents/runtime/designer/workspace/design-docs/T-001-design.md"],
      "files_modified": [],
      "issues_encountered": [],
      "handoff_notes": "实现者应先完成 JWT 中间件, 再做登录/注册接口。注意: refresh token 需存 httpOnly cookie。"
    }
  }
}
```

## 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `task_id` | string | 关联的任务 ID |
| `version` | number | 乐观锁版本号 |
| `last_updated` | ISO 8601 | 最后更新时间 |
| `stages` | object | 以阶段名为 key 的记忆快照集合 |

**阶段快照字段**: `agent` (执行角色), `started_at`/`completed_at` (时间), `summary` (2-5句摘要), `decisions` (关键决策及原因), `artifacts` (产出路径), `files_modified` (修改的源码), `issues_encountered` (问题), `handoff_notes` (交接备注)

## 自动记忆沉淀 (Auto-Capture)

**触发**: FSM 状态转移时 (post-tool-use hook 检测 task-board.json 中 status 变化)

**流程**: 检测变化 → 读取 Agent 上下文 → 提取字段 → 写入 memory → 更新 version

**自动提取**:
- `summary`: Agent 总结 (2-5 句) | `decisions`: "选择 X 因为 Y" 格式
- `files_modified`: 从 git diff | `issues_encountered`: 问题和解决方案
- `handoff_notes`: 交接要点 | `artifacts`: 产出文档路径

**注意**: 自动提取是 best-effort; 敏感信息自动脱敏; memory 文件不存在则自动创建

## 智能记忆加载 (Smart Loading)

Agent 切换时自动加载, 只加载**当前角色需要的字段**:

| 下游角色 | 加载字段 | 省略 |
|---------|---------|------|
| Designer (← Acceptor) | goals, description | — |
| Implementer (← Designer) | decisions, artifacts, handoff_notes | issues_encountered |
| Reviewer (← Implementer) | files_modified, decisions, summary | handoff_notes |
| Tester (← Reviewer) | files_modified, review issues, summary | decisions |
| Acceptor (← Tester) | 全部 stages 的 summary | 详细字段 |

加载后以可读文本呈现 (非原始 JSON):
```
📝 任务记忆: T-008
🏗️ 设计阶段 (Designer, 完成于 10:30):
  决策: 使用 post-tool-use hook 检测状态变化触发记忆保存
  交接: 修改 agent-post-tool-use.sh 添加 auto-capture 逻辑
```

**集成**: agent-switch 切换时 → 检查任务 → 读取 memory → 按角色过滤 → 格式化展示

## 操作

### 保存记忆 (⚡ 阶段转移时自动触发)

状态转移后, Agent **必须**保存记忆:

1. 读取 `.agents/memory/T-NNN-memory.json` (不存在则创建)
2. 在 `stages` 中添加/更新当前阶段快照, 填写所有字段
3. **🔒 脱敏处理** (写入前必须执行):

| 敏感类型 | 匹配模式 | 替换为 |
|---------|---------|--------|
| API Key | `AIza...`, `sk-...`, `ghp_...`, `AKIA...` | `[REDACTED:API_KEY]` |
| 密码/密钥 | `password=xxx`, `secret=xxx`, `token=xxx` | `[REDACTED:CREDENTIAL]` |
| 内网 IP | `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x` | `[REDACTED:INTERNAL_IP]` |
| SSH/连接串 | `ssh user@host`, `mysql://user:pass@host` | `[REDACTED:CONNECTION]` |
| 环境变量值 | `.env` 引用的值 | `[REDACTED:ENV_VALUE]` |

**原则**: 保留技术决策和上下文, 只替换秘密值。不确定时宁可替换。

4. version + 1, 更新 last_updated, 写入

**触发时机** (对应状态转移):

| 转移 | 保存阶段 | 保存者 |
|------|---------|--------|
| `designing → implementing` | designing | designer |
| `implementing → reviewing` | implementing | implementer |
| `reviewing → implementing` (退回) | reviewing | reviewer |
| `reviewing → testing` | reviewing | reviewer |
| `testing → accepting` | testing | tester |
| `testing → fixing` | testing | tester |
| `fixing → testing` | fixing | implementer |
| `accepting → accepted/accept_fail` | accepting | acceptor |
| 任何 → `blocked` | 当前阶段 | 当前 Agent |

### 加载记忆 (🔄 接手任务时自动执行)

读取 `.agents/memory/T-NNN-memory.json`, 存在则显示上下文摘要:
```
📝 任务记忆 — T-001: 用户认证系统
📌 上一阶段: designing (by designer), 完成: 2026-04-05 10:00
   摘要: 设计了基于 JWT 的用户认证系统...
   决策: JWT (移动端) / bcrypt (cost=12)
   📮 交接: 实现者应先完成 JWT 中间件, 再做登录/注册接口。
```

### 查看完整记忆

用户说 "查看记忆" / "任务上下文" / "memory" 时, 按时间顺序展示所有阶段记忆:
```
[1] designing — designer — 08:30 → 10:00
    摘要/决策/产出/问题 (每阶段一段)
```

### 更新记忆 (同一阶段内追加)

同一阶段有重要进展时: 读取 → 追加到 decisions/files_modified/issues_encountered → version+1 → 写入

## 与其他 Skill 的集成

- **agent-task-board**: 状态转移 → FSM 验证 → 写入 task-board → 同步 Markdown → 💾 保存记忆 → 通知下游
- **agent-switch**: 切换角色 → 检查 inbox → 扫描任务 → 📝 加载任务记忆 → 开始工作
- **agent-events**: 记忆事件记录到 events.db (`memory_save` / `memory_load`)

## 注意事项
- 乐观锁 (version 字段) | 记忆文件**应提交 git** (项目知识, 非临时状态)
- **🔒 写入前必须脱敏** | summary 和 handoff_notes 是最重要字段 — 确保信息密度高
- 阶段重复进入时, 追加 round 信息到 summary

---

## 搜索记忆

用户说 "搜索记忆 <关键词>" / "search memory <keyword>" 时:

**搜索范围**: `.agents/memory/T-NNN-memory.json` 所有文件

| 字段 | 权重 | 说明 |
|------|------|------|
| `decisions` | ⭐⭐⭐ | 过去的决策和原因 |
| `issues_encountered` | ⭐⭐⭐ | 踩过的坑 |
| `summary` | ⭐⭐ | 工作摘要 |
| `handoff_notes` | ⭐⭐ | 交接经验 |
| `files_modified` | ⭐ | 文件路径变更 |

**排序**: 精确匹配 decisions/issues 优先 → 同类阶段优先 → 最近任务优先

**上下文感知**: Agent 可不指定关键词, 从当前任务 description/goals 自动提取关键词搜索

**输出格式**:
```
🔍 搜索记忆: "redis"
[1] T-001 / implementing — issues_encountered
    "connect-redis v7 API 变了, 需要用 new RedisStore({client})"
[2] T-003 / implementing — decisions
    "Redis 缓存使用 ioredis, 更好的 cluster 支持"
```

---

## 项目级摘要

用户说 "项目摘要" / "project summary" / "lessons learned" 时:

读取所有 `T-NNN-memory.json` + `task-board.json`, 汇总生成:
- **架构决策** (从 designing.decisions 提取)
- **踩坑记录** (从 issues_encountered 提取)
- **技术栈选择** (从 decisions 聚合关键词)
- **文件修改热区** (从 files_modified 计数)

可选保存为 `.agents/memory/PROJECT-SUMMARY.md` (覆盖更新, 可提交 git)

---

## 项目记忆 (Project Memory)

跨任务持久化知识库。文件: `<project>/.agents/memory/project-memory.json`

### Schema (canonical example)

```json
{
  "version": 1,
  "last_updated": "2026-04-10T15:00:00Z",
  "tech_stack": {
    "language": "TypeScript", "runtime": "Node.js 20", "framework": "Express.js",
    "database": "PostgreSQL + Prisma ORM", "cache": "Redis (ioredis)",
    "testing": "Vitest + Playwright", "deployment": "Docker + Caddy",
    "ci_cd": "GitHub Actions", "other": ["pnpm", "ESLint", "Prettier"]
  },
  "architecture_decisions": [
    {
      "id": "ADR-001", "title": "选择 cookie session 而非 JWT",
      "date": "2026-04-05", "status": "accepted",
      "context": "纯 Web 应用, 不需要移动端支持",
      "decision": "express-session + connect-redis",
      "consequences": "服务端需维护 session 存储; 需配置 Redis",
      "source_task": "T-001", "superseded_by": null
    }
  ],
  "lessons_learned": [
    {
      "id": "LL-001", "date": "2026-04-05", "category": "dependency",
      "title": "connect-redis v7 API 变更",
      "description": "需要用 new RedisStore({client}) 而非 new RedisStore(client)",
      "impact": "high", "source_task": "T-001", "tags": ["redis", "breaking-change"]
    }
  ],
  "hot_files": [
    {
      "path": "src/routes/auth.ts", "modification_count": 5,
      "last_modified_by": "T-004", "last_modified_at": "2026-04-08T14:00:00Z",
      "risk_level": "high", "note": "认证核心路由, 修改需完整回归测试"
    }
  ]
}
```

### 字段说明

**tech_stack**: language, runtime, framework, database, cache, testing, deployment, ci_cd, other (string[])

**architecture_decisions (ADR)**: id (`ADR-NNN`), title, date, status (`proposed`/`accepted`/`deprecated`/`superseded`), context, decision, consequences, source_task, superseded_by

**lessons_learned**: id (`LL-NNN`), date, category (`dependency`/`testing`/`deployment`/`architecture`/`performance`/`security`/`other`), title, description, impact (`high`/`medium`/`low`), source_task, tags[]

**hot_files**: path, modification_count, last_modified_by, last_modified_at, risk_level (`high`≥5/`medium`≥3/`low`), note

### 自动更新 (Task Accepted 时触发)

任务 `accepted` → 读取 project-memory.json + T-NNN-memory.json → 提取更新:

1. **架构决策**: 从 designing.decisions 提取技术选型/架构模式级决策。同主题 ADR 结论一致→跳过, 不同→创建新 ADR + 旧 ADR 标 superseded
2. **经验教训**: 从 issues_encountered 提取可复现问题。去重 (按 tags/description 相似度)
3. **热点文件**: 从 files_modified 聚合, modification_count+1, 重算 risk_level
4. **技术栈**: 从 decisions 扫描 "使用/引入/选择/采用 X" 模式, 检测新技术 → 确认后写入

### 加载 (Agent Init 时触发)

按角色差异化:

| 角色 | 加载 | 省略 |
|------|------|------|
| acceptor | tech_stack, ADR(全部), hot_files | lessons_learned 详情 |
| designer | tech_stack, ADR(全部), LL(architecture类) | hot_files |
| implementer | tech_stack, ADR(accepted), LL(全部), hot_files | deprecated ADRs |
| reviewer | tech_stack, ADR(accepted), hot_files, LL(全部) | deprecated ADRs |
| tester | tech_stack(testing), LL(testing类), hot_files | ADRs |

**集成**: agent-switch/agent-init → 📝 加载任务记忆 → 🧠 加载项目记忆 → 开始工作

### 搜索 (`/memory search <keyword>`)

搜索 project-memory.json: ADR (title/context/decision) ⭐⭐⭐ | LL (title/description/tags) ⭐⭐⭐ | tech_stack ⭐⭐ | hot_files (path/note) ⭐

**联合搜索** ("搜索所有记忆"): 同时搜索项目记忆 + 所有任务记忆, 合并去重按权重排序

---

## Context Budget Management

Total context budget allocation by role:

| Source | Acceptor | Designer | Implementer | Reviewer | Tester |
|--------|----------|----------|-------------|----------|--------|
| System prompt | 5k | 5k | 5k | 5k | 5k |
| Project context | 10k | 15k | 10k | 10k | 10k |
| Task context | 10k | 20k | 15k | 20k | 15k |
| Memory (Top-6) | 5k | 10k | 5k | 10k | 5k |
| Code context | 5k | 10k | 40k | 50k | 20k |
| Conversation | 145k | 120k | 105k | 85k | 125k |

**Priority when budget tight**: System prompt (never cut) → Task goals/status → Memory results → Code context → Project context → Conversation (oldest first)

**Smart Compression** near limit: Preserve decisions/ADRs/code changes → Compress discussion turns to summaries → Keep recent 10 turns verbatim → Older turns → one-line summaries

---

## Future Plans: Memory System 2.0

> **Not yet implemented.** Planned three-layer architecture: Layer 1 (MEMORY.md per-role, permanent), Layer 2 (daily diary YYYY-MM-DD.md, 30-90 day lifecycle), Layer 3 (PROJECT_MEMORY.md, shared). Will include SQLite FTS5 indexing, temporal decay scoring, and auto-promotion of high-signal diary entries to long-term memory.

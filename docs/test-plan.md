# CodeNook — 测试计划文档

> **状态**：基于 `architecture.md`（设计稿）编写。本文档不重述设计，只描述**如何验证 v6 按设计运行**。
>
> **追踪约定**：用例编号格式 `<子系统>-NNN`，章末标注 `→ 设计依据：架构文档 §X.Y`。
>
> **术语**：`<workspace>` 指被 `init.sh` 初始化的根目录；`<plugin>` 指已安装的 plugin 名；`MS` = Main session；`OT` = orchestrator-tick；`SR` = session-resume。

---

## 目录

1. 测试金字塔与覆盖矩阵
2. 关键测试用例
   - A. Main session 纪律
   - B. Router
   - C. Orchestrator-tick
   - D. Session-resume
   - E. Plugin 安装 / 升级 / 卸载 / 安全扫描
   - F. 模块化子系统（memory / skills / config / history / queue）
   - G. Task + target_dir
   - H. v5 → v6 迁移
   - M. 模型路由与探测（Model Routing & Probe）
3. 测试数据准备
4. 自动化策略
5. 可观测性与诊断
6. 风险测试矩阵
7. 已识别的可测试性歧义（反馈给设计文档）

---

## 1. 测试金字塔与覆盖矩阵

### 1.1 分层

| 层 | 关注点 | 数量级 | 运行环境 | 主要工具 |
|---|---|---|---|---|
| **单元测试（L1）** | 单个 builtin skill 算法、单个 validator gate、安全扫描单条规则、config 4 层合并算法、router 输出 schema 校验、entry-questions 解析 | 数百级 | 本机 / CI；纯文件 + bash + jq + yq；mock LLM | bats-core / shellspec / pytest（如有 Python helper） |
| **集成测试（L2）** | `init.sh` 各子命令端到端；plugin 安装管线（scaffold→pack→install→list→remove→reinstall→force）；router self-scan；OT 单跳；SR 单跳；config-resolve 端到端；HITL queue 写入/弹出 | 数十级 | 临时 workspace；mock LLM 或受控 Stub agent | bats + 自研 LLM stub |
| **系统测试（L3 / E2E）** | 完整 plugin 装→任务创建→phase 推进→蒸馏→HITL→accept；多 plugin 共存切换；卸载/重装/升级；secrets 隔离；多 task 并发 | 个位数到 20 用例 | 干净 workspace + 真 LLM（限定模型）或高保真 Stub | 端到端脚本 + 断言 + artifact diff |
| **回归套件** | v5 关键场景（dev plugin 6 phase 流水线 / fanout / dual_mode review-iteration / HITL accept）在 v6 上重跑 | 5–10 个固定剧本 | 同 L3 | 历史档案；v5 源码已移除（v0.11.1），由 codenook-core e2e 套件覆盖 |

### 1.2 覆盖矩阵（设计章节 → 测试层）

| 设计章节 | L1 | L2 | L3 |
|---|---|---|---|
| §2 分层模型 | — | E-列表/移除子命令 | E2E 多 plugin 共存 |
| §3 Main session 控制流 | A-001..A-010 | A-011..A-014 | H-001（v5→v6 e2e） |
| §3.1 编排器拆分总览 | A-021..A-025 | C-001..C-006 | H-001 |
| §3.1.3 orchestrator-tick | C-001..C-020（单跳算法）| C-021..C-030（多跳序列） | H-001 |
| §3.1.4 session-resume | D-001..D-008 | D-009..D-012 | H-001 |
| §3.1.7 dispatch 协议 | A-006..A-010 | — | — |
| §3.2.2 memory 三层 | F-001..F-008 | F-009..F-012 | F-051（plugin 切换隔离） |
| §3.2.3 skills 四类 | F-013..F-020 | F-021..F-024 | F-051 |
| §3.2.4 config 4 层 | F-025..F-040（合并算法 + schema） | F-041..F-046（自动 mutator） | E-061（升级保留 overrides） |
| §3.2.5 history 单时间线 | F-047..F-049 | — | — |
| §3.2.6 queue / hitl-queue | F-050..F-052 | C-016..C-018 | — |
| §4 + §4.1 + §4.2 router | B-001..B-008（schema/字段） | B-009..B-016（self-scan） | B-017（端到端含 ask_user） |
| §5 plugin 契约 | E-001..E-008（schema） | E-021..E-030（结构校验） | — |
| §7 安装接口 | E-009..E-012 | E-021..E-040 | E-061..E-065 |
| §7.4 12 个 gates | E-021..E-040（每 gate 至少 1 反例 + 1 正例） | — | — |
| §7.4.1 安全扫描 | E-041..E-052（每规则反例） | E-053..E-055 | — |
| §8 task + target_dir | G-001..G-010 | G-011..G-015 | G-016 |
| §9 v5→v6 迁移 | — | H-002..H-004（文件审计） | H-001（v5 剧本 e2e） |
| **§3.2.4.1 模型分配 5 层链 + Router 例外 + task-config-set** | **M-006..M-018, M-019..M-022** | **M-011..M-018**（5 层链 + router 例外 + task-config-set） | **M-024..M-025（多层 provenance）** |
| **§3.2.4.2 模型探测 + tier 分级 + provenance** | **M-001..M-010, M-023..M-025** | **M-001..M-005（probe + TTL + refresh-models）** | — |

→ 设计依据：架构文档 §2、§3、§3.1、§3.2、§4、§5、§7、§8、§9

---

## 2. 关键测试用例

> 编号 = 子系统前缀 + 三位序号。所有用例均给出 **前置条件 / 步骤 / 期望** 三段。LLM 决策类用例用 **mock LLM 模式**（注入固定响应 JSON）和 **真 LLM 模式**（允许漂移容忍），各跑一份。

### A. Main session 纪律 （§3 + §3.1 + §3.1.7）

**A-001 — chat 输入不创建任务**
- 前置：干净 workspace，已 `init.sh` 完成。
- 步骤：MS 收到 `"什么是 RAG？"`。
- 期望：MS 内联回答；`tasks/` 目录无新增；`history/sessions/latest.md` 不出现 `task_create` event。

**A-002 — task candidate 必须经 ask_user 确认**
- 步骤：MS 收到 `"帮我把 xueba 的 list 命令加 --tag 过滤"`。
- 期望：MS 调 `ask_user`；用户未确认前 `tasks/T-*` 不出现；`router` agent 未被 dispatch（检查 `history/router-decisions.jsonl` 无新条目）。

**A-003 — 用户 decline 后退回 chat**
- 步骤：A-002 之后用户回 `"不用，先聊聊"`。
- 期望：无任务、无 router 调用、MS 继续对话。

**A-004 — 用户 accept 后 handoff 给 router**
- 步骤：A-002 之后用户回 `"好，建任务"`。
- 期望：恰好一次 router dispatch；`router-decisions.jsonl` 追加一行；MS 自身没有读取 `plugins/*/plugin.yaml`（见 A-007 文件审计）。

**A-005 — `/task` 显式指令绕过启发式但仍走 router**
- 步骤：用户输入 `"/task 写一篇博客"`。
- 期望：跳过 chat-vs-task 启发式；ask_user 仍可省略（按 shell.md 显式指令直通）；router 被 dispatch；MS 不挑 plugin。

**A-006 — Main session 不内联 sub-agent prompt**
- 工具：抓取 MS 实际发出的 dispatch payload（开发期通过 `history/dispatch-trace.jsonl` 落盘）。
- 期望：每次 dispatch 文本 ≤ 200 字；不含任何 `phases.yaml` / `roles/*.md` 节选；只含 `Profile:` + `Input:` 字段（见 §3.1.7 示例）。

**A-007 — Main session 不读 plugin 文件（文件审计）**
- 工具：用 `strace -e openat -p <MS-pid>` 或 `fs-usage`（macOS）记录 MS 进程的 open() 调用。
- 期望：MS 进程从未 open `<workspace>/.codenook/plugins/**`。

**A-008 — Main session 不读 state.json / queue / locks**
- 同 A-007 工具。
- 期望：MS 进程从未 open `tasks/*/state.json`、`queue/`、`locks/`、`hitl-queue/`。读取交由 SR 与 OT helper agent。

**A-009 — Main session 不构造 manifest**
- 工具：检查 dispatch payload 是否含 manifest 字段。
- 期望：MS 发出的 payload 不含 `manifest:` 字段；任何 manifest 由 OT 内部生成。

**A-010 — Main session 不持有 router 模型选择**
- 工具：grep MS 发出的 dispatch payload 中是否包含 `model:` 字段。
- 期望：不含；router agent 自己从 config-resolve 获取自己应使用的模型。

**A-011 — Context 稳态 ≤ 5K（§3.1.5）**
- 步骤：mock 多回合对话脚本（≥30 轮，每轮触发 1 次 OT）；测量 MS 上下文 token 数。
- 期望：稳态 ≤ 5K + 用户对话历史；shell.md 加载 1 次；SR 摘要 ≤ 500 字；每轮 OT summary ≤ 200 字。

**A-012 — shell.md ≤ 3K（硬约束）**
- 测：`wc -c .codenook/core/shell.md`。
- 期望：≤ 3072 字节。

**A-013 — Handoff payload schema 验证**
- 期望：MS → router 的 payload 必须含 `task_description`、`user_context`，可选 `optional_user_hint`；多余字段不被注入。

**A-014 — 多任务并发时 MS 一回合最多 1 次 OT 调用**
- 步骤：3 个 active task 并存，用户发一句"继续"。
- 期望：MS 仅触发 1 次 OT（针对 `current_focus`），不批量推进所有任务。

→ 设计依据：架构文档 §3、§3.1.5、§3.1.7

---

### B. Router （§4 + §4.1 + §4.2）

**B-001 — JSON schema 校验**
- mock router 返回 `{plugin, confidence, rationale, alternates}`。
- 期望：调用方 (MS / OT) 拒绝缺字段、拒绝 confidence 越界 (>1 / <0)、拒绝未知 plugin。

**B-002 — confidence 字段一致性**
- 期望：`alternates[*].confidence` 均 < `confidence`；总和 ≤ 1.0；同 plugin 不重复出现。

**B-003 — 单 plugin catalog 命中**
- 前置：仅装 `development` + `generic`；输入 `"实现一个 Python CLI"`。
- 期望：`plugin == "development"`，confidence ≥ 0.75。

**B-004 — 含混路由 → 走 ask_user 确认**
- 前置：装 `development` + `writing` + `generic`；输入 `"帮我整理一下接口设计"`（编码 + 文档双关）。
- 期望：confidence < `router.confidence_threshold`（0.75）；MS 通过 ask_user 让用户在 alternates 中选。

**B-005 — Router 无匹配 → fallback generic**
- 输入：`"占星运势如何？"`
- 期望：`plugin == "generic"`；rationale 注明 fallback。

**B-006 — anti_examples 排他**
- 前置：development plugin 含 `anti_examples: ["写一篇博客"]`；输入 `"写一篇博客介绍 RAG"`。
- 期望：development 不被选中（即使 keywords 命中"博客"亦不算）。

**B-007 — User hint 不强制**
- 前置：用户 prompt 含 `"用 writing plugin 写..."`，但实际任务描述是代码改造。
- 期望：router 可拒绝 hint；rationale 必须明确说明 override。

**B-008 — disabled plugin 不入 catalog**
- 前置：`config.yaml` 设 `plugins: { writing: { enabled: false } }` 或 `plugins.disabled: [writing]`。
- 期望：catalog 不含 writing；router 不会返回它。

**B-009 — Self-scan 每次 dispatch 都 fresh**
- 步骤：dispatch 1 → 安装新 plugin → 立刻 dispatch 2，无 MS 重启。
- 期望：dispatch 2 catalog 包含新 plugin（无缓存）。

**B-010 — broken plugin 跳过**
- 步骤：手工破坏 `plugins/foo/plugin.yaml`（YAML 语法错）。
- 期望：catalog 不含 foo；router 可继续工作；同时 `init.sh --list-plugins` 标记 foo 为 broken。

**B-011 — Catalog 体积上限**
- 前置：装 20 个 plugin。
- 期望：构建后的 catalog 序列化 ≤ 8KB；router 上下文未爆。

**B-012 — Builtin generic 始终在末尾**
- 期望：catalog 顺序的最后一项总是 `generic`。

**B-013 — Path traversal 防御（plugin.yaml 攻击）**
- 前置：恶意 plugin manifest 中 `examples: ["../../../etc/passwd"]` 或 routing 字段含 `../`。
- 期望：router self-scan 阶段 **不解引用** 字符串内容（仅作为分类语料）；无文件被读出。

**B-014 — Plugin.yaml 含路径字段被 schema 校验**
- 前置：恶意 plugin manifest `data_glob: ["../../etc/*"]`。
- 期望：安装期被 §7.4 gate 12（manifest 合理性）拦截，根本不会进入 router。本用例验证安装→router 的端到端兜底。

**B-015 — 大模型偏向防御**
- mock：注入 router 返回 `confidence=0.99` 但 rationale 与任务无关。
- 期望：MS 仍会显示 rationale 给用户；用户可推翻；推翻事件写 `router-decisions.jsonl`（user_override 字段）。

**B-016 — Router 不写任何 plugin 文件**
- 工具：审计 router agent 的 fs 写操作。
- 期望：仅写 `router-decisions.jsonl`；从不写 `plugins/`、`memory/`、`tasks/`。

**B-017 — E2E：低 confidence → 用户确认 → 任务创建**
- 期望：完整链路一次跑通；记录到 history。

→ 设计依据：架构文档 §4、§4.1、§4.2

---

### C. Orchestrator-tick （§3.1.3）

**C-001 — Phase 启动（首次推进）**
- 前置：刚 mount 的任务，phase=clarify，无 agent 在跑。
- 期望：tick 派发 `clarifier` agent；写 `state.dispatched_agent_id`；返回 `next_action: wait_for_agent`。

**C-002 — Phase 推进（输出就绪 → 下一步）**
- 前置：`phase-1-clarifier-summary.md` 已写；verdict=ok。
- 期望：tick 查 `transitions.yaml` → `clarify.clarifier.ok → design`；写 `phase: design`，派发 `designer`。

**C-003 — Validator 派发条件**
- 前置：phase 输出已就绪、未校验、`phases.yaml` 声明 `post_validate`。
- 期望：tick 派发 validator agent，而不是直接推进。

**C-004 — Validator 失败回退**
- 前置：validator agent 返回 verdict=fail。
- 期望：tick 不推进；按 transitions 表回到对应 phase（如 implement）；iteration++。

**C-005 — HITL gate 拦截**
- 前置：phase=accept 通过，next 为 ship；hitl-gates.yaml 声明 `pre_ship_review`。
- 期望：tick 写入 `hitl-queue/T-NNN-pre_ship_review.json`；返回 `status: awaiting_hitl, message_for_user: "..."`；不推进 phase。

**C-006 — HITL approval 后推进**
- 前置：hitl 决策文件 `decisions/<gate>.json` 已写 approved。
- 期望：下一次 tick 推进到 ship；删除/归档 hitl-queue entry。

**C-007 — HITL auto_approve_if 命中**
- 前置：gate `design_signoff` 配置 `auto_approve_if: ["task.priority in [low]"]`，任务 priority=low。
- 期望：tick 不写 hitl-queue，直接推进；history 中写 auto_approve event 并标注 reason。

**C-008 — 并发槽位上限**
- 前置：config `concurrency.max_inflight_per_task=2`，已有 2 个 sub-agent 在跑。
- 期望：tick 不再派发；返回 `next_action: wait`。

**C-009 — 跨 task 全局并发上限**
- 前置：`concurrency.max_global=4`，已有 4 个 agent 在跑（跨 plugin）。
- 期望：tick 拒绝派发；写 history `throttled` event。

**C-010 — Subtask fan-out**
- 前置：planner verdict=`decomposed`，产出 `decomposition/plan.md` 含 N 子任务定义。
- 期望：tick 创建 N 个 subtask（继承 `plugin / plugin_version / target_dir`）；父任务进入 wait_subtasks 状态；queue 出现 N 个 entry。

**C-011 — Subtask 全部完成 → 父任务汇聚**
- 期望：tick 检测全部 subtasks done；父任务推进到下一 phase；不重复派发。

**C-012 — Dispatch-audit 触发条件**
- 前置：本轮 dispatch 即将创建第 K 个 sub-agent（K = 配置阈值，例如 5）。
- 期望：tick 在派发前调 `dispatch-audit` builtin skill；audit 报错则阻断 dispatch。

**C-013 — Preflight 拦截缺字段**
- 前置：phase=design 的 entry-questions 要求 `constraints, non_goals`，state 中缺 `non_goals`。
- 期望：tick 调 preflight → 失败；返回 `status: blocked, message_for_user: "missing field non_goals"`；不派发。

**C-014 — Preflight 拦截 target_dir 失效**
- 前置：`target_dir` 已被外部删除。
- 期望：tick 通过 preflight 检测并 abort，标记 task `status=blocked`。

**C-015 — Tick 是无状态的（重入安全）**
- 步骤：手工连续触发 2 次 tick（无新事件发生）。
- 期望：第 2 次为 no-op；不重复派发；history 不出现 duplicate dispatch。

**C-016 — 队列 entry 含 plugin tag**
- 期望：每条 queue entry 含 `plugin: "<name>"` 字段（§3.2.6）。

**C-017 — HITL queue 跨 plugin 隔离展示**
- 前置：dev 任务和 writing 任务同时在 HITL。
- 期望：`hitl-queue/` 文件名 / 内容含 plugin 字段；dashboard 渲染按 plugin 分组（用 `jq 'group_by(.plugin)'` 验证）。

**C-018 — Tick summary ≤ 200 字（A-006/A-011 关联）**
- 期望：返回给 MS 的 message ≤ 200 字；详细信息只写 history。

**C-019 — Tick 写 orchestrator-log.jsonl**
- 期望：每次 tick 至少 1 行；含 `task_id, phase_before, phase_after, action, agent_id?, verdict?`。

**C-020 — Distill 在任务完成时被触发**
- 前置：phase=ship → complete。
- 期望：tick 派发 distiller agent；不阻塞 main session。

**C-021..C-030 多跳序列（集成层）**
- C-021：clarify→design→plan(single)→implement→test pass→accept→validate→ship 全链路 mock。
- C-022：implement→review needs_fixes→implement(iter2)→review looks_good→test。
- C-023：fanout 后 3 个 subtask 并行 → 全部 pass → 汇聚。
- C-024：phase 中途 dual_mode 由 serial 切 parallel（或反之）应被 immutable 拒绝（如设计如此约束）。
- C-025：preflight 缺字段被拦后，用户补字段 → 第 2 次 tick 通过。
- C-026：HITL 拒绝（rejected with reason）→ 回到上一 phase 并 iter++。
- C-027：HITL 超时（如配置）→ 升级或重新提示，按 hitl-gates 配置。
- C-028：max_iterations 命中 → 任务标记 blocked，hitl 必须人工裁决。
- C-029：dispatch-audit fail → 任务进入 blocked，不重试。
- C-030：tick 在缺 plugin（plugin 被卸载但 task 存活）下 → 标记 task `plugin_missing` 而不是崩溃。

→ 设计依据：架构文档 §3.1.3、§3.1.5、§3.1.7、§3.2.6、§5、§8

---

### D. Session-resume （§3.1.4）

**D-001 — 新会话首次输入前调用一次**
- 期望：MS 在收到第一条用户输入但**未回复前**派 SR；history 出现一条 `session_resume_invoked`。

**D-002 — 同会话第二条输入不再调用 SR**
- 期望：仅在 session 首次调用一次。

**D-003 — 摘要 ≤ 500 字**
- 测：`wc -c` SR 返回的 message。
- 期望：≤ 500 字（按 char 统计；中文字符按 1 计）。

**D-004 — 无 active_tasks 时摘要为简短欢迎**
- 期望：不读 tasks 目录；不读 latest.md（如不存在）。

**D-005 — 多 active_tasks 摘要含每个 1 行**
- 期望：每个 task 一行：`T-NNN [plugin] phase=<x> status=<y>`。

**D-006 — current_focus 高亮**
- 前置：`state.json.current_focus=T-007`。
- 期望：摘要中 T-007 排首位且加 marker。

**D-007 — 缺失 latest.md 不崩溃**
- 期望：fallback 到 `state.json` 即可；返回部分摘要。

**D-008 — SR 不写任何状态文件**
- 工具：审计 SR agent 进程的 fs 写操作。
- 期望：仅写 `history/session-resume.jsonl`（如配置）；不动 state.json / tasks/。

**D-009 — SR 不调 LLM（纯文件 → 模板化）**
- 期望：SR 实现是确定性脚本（builtin skill），不发生 LLM 调用。
- 备注：若设计允许 SR 用 LLM 做归纳，则改为校验 token 上限 ≤ 800 input。

**D-010 — SR 在大量 task 下截断**
- 前置：50 个 active_tasks。
- 期望：摘要仍 ≤ 500 字；只列前 N（按 last_updated 排序）+ "(+M more)"。

**D-011 — 状态恢复正确（往返）**
- 步骤：在 v6 里完整建任务、推进 3 phase；杀掉会话；再开新会话；触发 SR。
- 期望：摘要恢复到正确 phase；后续 OT 推进无误。

**D-012 — SR 失败兜底**
- 前置：state.json 损坏。
- 期望：SR 返回 `"workspace state unreadable, please run init.sh --doctor"`；MS 不阻塞，可继续对话。

→ 设计依据：架构文档 §3.1.4

---

### E. Plugin 安装 / 升级 / 卸载 / 安全扫描 （§7 + §7.4 + §7.4.1）

#### E.1 安装基础

**E-001 — Tarball 本地路径安装**
- 步骤：`init.sh --install-plugin ./good-plugin-0.1.0.tar.gz`
- 期望：解压到 `.codenook/plugins/<name>/`；`history/plugin-installs.jsonl` 追加 1 行；staging 被清理；返回码 0。

**E-002 — Zip 本地路径安装**
- 同上，源为 `.zip`。

**E-003 — URL 安装**
- 步骤：使用本地 HTTP server 提供 tarball；`--install-plugin http://127.0.0.1:8000/...tar.gz`。
- 期望：curl 进 staging；后续同 E-001。

**E-004 — `--sha256` 校验通过**
- 期望：sha256 匹配 → 安装。

**E-005 — `--sha256` 校验失败**
- 步骤：传错误 sha256。
- 期望：中止；staging 保留；非零退出；error code 标识 sha256 不匹配。

**E-006 — 已安装且无 `--force` → 拒绝**
- 期望：报错 "already installed; use --force or --remove-plugin"；状态不变。

**E-007 — `--force` 升级覆盖**
- 期望：`plugins/<name>/` 内容被新版本覆盖；旧版本归档至 `.codenook/history/plugin-versions/<name>/<old-version>/`。

**E-008 — `--list-plugins` 输出**
- 期望：列出 name / version / status (ok|broken|disabled)；含 generic。

**E-009 — `--remove-plugin generic` 拒绝**
- 期望：报错；generic 不可移除（§7.2）。

**E-010 — `--reinstall-plugin <name>`**
- 期望：在不重新下载的前提下重跑校验；通过则 remount；失败保持现状。

**E-011 — `--scaffold-plugin foo` 产出可工作的骨架**
- 期望：生成 `./foo-plugin/` 含所有必需文件；`init.sh --pack-plugin ./foo-plugin/` 通过 12 gates。

**E-012 — `--pack-plugin` 复用安装校验流水线**
- 期望：scaffold 出来的骨架若被破坏（删 phases.yaml）→ pack 失败，错误码与 install 相同。

#### E.2 12 gates 反例（每 gate 至少 1 用例）

| 用例 | Gate | 反例构造 | 期望 |
|---|---|---|---|
| **E-021** | 1 | tarball 解压根无 plugin.yaml | abort + code G1 |
| **E-022** | 2 | plugin.yaml 是 `: : :`（YAML 错） | abort + code G2 |
| **E-023** | 3 | 缺 `summary` 字段 | abort + code G3 |
| **E-024** | 3 | `version: foo`（非 semver） | abort + code G3 |
| **E-025** | 3 | 缺 `data_layout` | abort + code G3 |
| **E-026** | 4 | `name: 1bad`（不匹配 regex） | abort + code G4 |
| **E-027** | 4 | `name: BAD-NAME`（大写） | abort + code G4 |
| **E-028** | 5 | `codenook_core_version: ">=99"` | abort + code G5 |
| **E-029** | 6 | 缺 `phases.yaml` | abort + code G6 |
| **E-030** | 6 | `roles/` 为空 | abort + code G6 |
| **E-031** | 7 | `phases.yaml` 引用未定义 role 文件 | abort + code G7 |
| **E-032** | 7 | `transitions.yaml` 引用不存在的 phase id | abort + code G7 |
| **E-033** | 8 | transitions 出现孤岛 phase（终止 phase 不可达） | abort + code G8 |
| **E-034** | 9 | `entry-questions.yaml` schema 错（required_fields 不是数组） | abort + code G9 |
| **E-035** | 9 | `hitl-gates.yaml` 中 `auto_approve_if` 不是字符串数组 | abort + code G9 |
| **E-036** | 10 | 含恶意 symlink（见 E-041） | abort + code G10 |
| **E-037** | 11 | `name: core` | abort + code G11 |
| **E-038** | 11 | `name: codenook` | abort + code G11 |
| **E-039** | 12 | 解压 ≥ 11 MB | abort + code G12 |
| **E-040** | 12 | 调高 `plugins.max_size_mb=20` 后同包通过 | install ok |

#### E.3 安全扫描反例（§7.4.1）

| 用例 | 规则 | 反例构造 | 期望 |
|---|---|---|---|
| **E-041** | symlink | 包含 `roles/foo.md -> /etc/passwd` | abort；security-report.md 列出 finding |
| **E-042** | 隐藏文件白名单 | 含 `.env` | abort |
| **E-043** | 隐藏文件白名单（正例） | 含 `.gitignore` | install ok |
| **E-044** | path traversal in YAML | `data_glob: ["../../*"]` | abort |
| **E-045** | path traversal 绝对路径 | `data_glob: ["/etc/*"]` | abort |
| **E-046** | 可执行文件越界 | `roles/foo.sh` 设置 `+x` | abort |
| **E-047** | `skills/` 内 world-writable | `skills/x/run.sh` 模式 0777 | abort |
| **E-048** | 危险 shebang | `#!/usr/bin/perl` | abort |
| **E-049** | 危险关键词 `curl ... \| sh` | abort |
| **E-050** | 危险关键词 `eval $(...)` | abort |
| **E-051** | secret 泄露 | `roles/x.md` 含 AWS key 形 `AKIA[0-9A-Z]{16}` | abort；report 含命中位置 |
| **E-052** | secret 泄露 | 嵌入 PEM 私钥 | abort |
| **E-053** | `--allow-warnings` 仅降级非关键 | path traversal 是关键 → 仍 abort | abort |
| **E-054** | `--allow-warnings` 放过非关键 | 单纯权限 0644 → 通过 | install ok |
| **E-055** | staging 在失败时保留 | 任意 abort 后 `.codenook/staging/<rand>/` 仍在 | 路径打印在 stderr |

#### E.4 升级 / 卸载

**E-061 — `--force` 升级保留 `memory/<p>/` 与 overrides**
- 步骤：装 dev v0.1 → 在 `memory/development/` 蒸馏出文件 → `config.yaml.plugins.development.overrides` 含自定义 → 装 dev v0.2 `--force`。
- 期望：`plugins/development/` 内容更新；`memory/development/` 完整保留；`overrides` 段未被擦除；`history/plugin-installs.jsonl` 追加 upgrade 条目。

**E-062 — `--remove-plugin <p>` 归档 memory**
- 期望：`memory/<p>/` 被移到 `memory/.archived/<p>-<ts>/`；不删除；`config.yaml.plugins.<p>` 段被移除；history 保留（带 plugin tag）。

**E-063 — `--remove-plugin <p>` 阻止当 active task 仍引用该 plugin**
- 前置：T-007 plugin=writing，状态 in_progress。
- 期望：`--remove-plugin writing` 拒绝；提示先归档/完成相关任务，或加 `--force-orphan`（如设计有此 flag；否则拒绝即可）。

**E-064 — Reinstall 不丢 memory**
- 同 E-061，但用 `--reinstall-plugin`。

**E-065 — 升级跨大版本走 `--force`**
- 期望：core_version 约束仍校验；不绕过 §7.4。

→ 设计依据：架构文档 §7、§7.2、§7.2.1、§7.3、§7.4、§7.4.1、§7.6、§3.2.8

---

### F. 模块化子系统 （§3.2）

#### F.1 Memory 三层路由（§3.2.2）

**F-001 — shipped 只读**
- 步骤：尝试由 distiller 写入 `plugins/<p>/knowledge/`。
- 期望：被拒（fs 权限或 distiller policy 拦截）。

**F-002 — workspace promote 命中条件**
- 前置：plugin.yaml `promote_to_workspace_when: ["topic in [environment]"]`；distiller 产出 topic=environment 的知识。
- 期望：写入 `<workspace>/knowledge/by-topic/...`，不写 plugin-local。

**F-003 — promote 未命中默认 plugin-local**
- 期望：写入 `memory/<p>/by-topic/...`。

**F-004 — plugin-local 隔离**
- 前置：dev 与 writing 同时存在。
- 期望：dev 蒸馏不出现于 `memory/writing/`；反之亦然。

**F-005 — Sub-agent 按 consumes 顺序读**
- 期望：consumes=[workspace, plugin_shipped, plugin_local] → 实际 open 顺序与之一致；总加载 ≤ 5K。

**F-006 — Retention `keep_last 50` 生效**
- 前置：在 `by-role` 写入 60 个文件。
- 期望：distiller GC 后保留最新 50 个；history 记录被 GC 的 10 个文件名。

**F-007 — task-scoped memory 不污染 plugin-local**
- 期望：`tasks/T-NNN/memory/` 在任务完成后归档而非合入 `memory/<p>/`（除非 distiller 显式 promote）。

**F-008 — Memory 路由策略可被 schema 校验**
- 期望：`promote_to_workspace_when` 表达式语法非法 → 安装期被 §7.4 gate 9 拦截。

**F-009..F-012**：跨 plugin 切换 e2e；distiller mock 注入；retention GC 集成。

#### F.2 Skills 四类路径（§3.2.3）

**F-013 — builtin 优先级**
- 期望：`builtin/sec-audit` 总是可用；与 plugin-shipped `dev/sec-audit` 冲突时 builtin 仍以 `builtin/<skill>` 命名访问。

**F-014 — plugin-shipped 仅在该 plugin 激活时可用**
- 前置：dev plugin 自带 `test-runner`；writing 任务尝试调 `development/test-runner`。
- 期望：被拒绝（不在当前 plugin 命名空间）。

**F-015 — workspace-custom 跨 plugin 共享**
- 期望：`skills/custom/<x>` 在任意 plugin 任务下都可被引用。

**F-016 — plugin-local-custom 隔离**
- 前置：dev 蒸馏出 `memory/development/skills/deploy-to-prod`。
- 期望：writing 任务不可见、不可调。

**F-017 — 命名冲突解析**
- 前置：`skills/builtin/foo` 与 `plugins/dev/skills/foo` 同名；激活 dev。
- 期望：调用方写 `builtin/foo` 或 `dev/foo`；裸 `foo` 触发歧义错误（参见 §10 开放问题 2 的 v6 决议：plugin 命名空间 `<plugin>/<skill>`）。

**F-018 — 自动蒸馏写到 plugin-local**
- 期望：默认 `default_target: plugin_local`。

**F-019 — promote_to_workspace_when 命中**
- 前置：tags 含 `generic`。
- 期望：写到 `skills/custom/`。

**F-020 — Skills 蒸馏审计写 `history/skills-audit.jsonl`**

**F-021..F-024**：集成层，构造完整调用链路。

#### F.3 Config 4 层合并（§3.2.4）

**F-025 — Layer 0 兜底单测**
- 步骤：删除所有 config 文件，调 `config-resolve plugin=development`。
- 期望：返回 builtin 默认（如 main=opus-4.7）。

**F-026 — Layer 1 覆盖 Layer 0**
- 前置：plugin `config-defaults.yaml` 设 `models.main: gpt-5.4`。
- 期望：merged.models.main = gpt-5.4。

**F-027 — Layer 2 覆盖 Layer 1**
- 前置：`config.yaml.defaults.models.main: opus-4.7`。
- 期望：opus-4.7 胜出。

**F-028 — Layer 3 覆盖 Layer 2**
- 前置：`config.yaml.plugins.development.overrides.models.reviewer: gpt-5.4-mini`。
- 期望：reviewer = gpt-5.4-mini。

**F-029 — Layer 4 任务级覆盖**
- 前置：`tasks/T-007/state.json.config_overrides.models.reviewer: gpt-4.1`。
- 期望：在 T-007 上下文 reviewer=gpt-4.1；其他任务不受影响。

**F-030 — 深合并默认行为**
- 前置：高层只覆盖 `models.reviewer`，低层 `models.main` 不变。
- 期望：merged 同时含两者。

**F-031 — `merge: replace` 标记字段**
- 前置：schema 标 `hitl.gates: { merge: replace }`；高层 `gates: [accept]`，低层 `gates: [design, accept]`。
- 期望：merged = `[accept]`（不并集）。

**F-032 — Schema 校验未知顶层 key 报错（决议 #45）**
- 前置：`config.yaml` 顶层加 `weird_key: 1`。
- 期望：`config-validate` 报 `unknown_top_key` 错；OT 拒绝执行 phase；MS 提示用户修正。
- 白名单（顶层只允许这 10 个 key）：`models, hitl, knowledge, concurrency, skills, memory, router, plugins, defaults, secrets`。其它 key 一律拒绝（包括驼峰 / 复数变体）。

**F-033 — Schema 校验类型错误**
- 前置：`models.main: 42`（应为字符串）。
- 期望：报错。

**F-034 — Disabled plugin 段被尊重**
- 期望：`plugins.<p>.enabled=false` → router 不上 catalog（与 B-008 联动）。

**F-035 — Secrets 不进 git**
- 测：仓库根 `.gitignore` 含 `.codenook/secrets.yaml`；`git status` 干净状态下加 secret 不被 staged。

**F-036 — secrets-resolve 注入 env**
- 期望：sub-agent 子进程 env 中含 secrets，但 secrets 文件**未被读到 main session 上下文**。

**F-037 — secrets 不出现在 history**
- 工具：grep history 全部 jsonl。
- 期望：无 API key、无 PEM 字串。

**F-038 — config 解析时机**
- 期望：MS 不调 `config-resolve`；只有 sub-agent self-bootstrap 才调（用 fs 审计验证）。

**F-039 — task 创建时快照（§8 plugin_version）**
- 期望：`state.json.plugin_version` 与 `state.json.config_snapshot_hash`（如有）记录。

**F-040 — Layer 隔离回归**
- 期望：T-007 修改 `config_overrides` 不影响 T-008。

**F-041 — Auto config-mutator 写入 overrides**
- 前置：distiller 建议 `models.reviewer = gpt-5.4-mini`；当前实际为 gpt-5.4。
- 期望：`plugins.<p>.overrides.models.reviewer` 被写入；`history/config-changes.jsonl` 追加 1 行（含 actor=distiller, reason=...）。

**F-042 — Mutator 幂等**
- 期望：建议与现值相同 → 不写、不发 history。

**F-043 — Mutator 不写 secrets.yaml**

**F-044 — Mutator 触发 schema 校验**
- 前置：建议未知 key。
- 期望：拒绝写入；history 记录 rejection。

**F-045 — Mutator 写入与 history 同步原子化**
- 期望：要么两者都成功，要么都失败（用 fs lock）。

**F-046 — 任务级覆盖不被 mutator 触及**
- 期望：mutator 只动 Layer 3；从不动 Layer 4。

**F-053 — Schema-driven merge（`merge: append` / list `merge: deep`）—— M5 才启用**
- 状态：**deferred to M5**；M1 不实现（M1 的 `config-resolve` 统一按 deep-merge + 列表 replace，见架构 §3.2.4 M1 简化口径）。
- 前置：plugin `config-schema.yaml` 给 `knowledge.consumes` 标 `x-merge: append`；Layer 1 `consumes=[a,b]`，Layer 2 `consumes=[b,c]`。
- 期望（M5 起）：merged `consumes=[a,b,c]`（追加去重保序，不被 replace）；同理给 list 标 `x-merge: deep` 时元素按 key 递归合并。M5 DoD #8 要求本用例通过。

#### F.4 History 单时间线 + tag（§3.2.5）

**F-047 — 每条 entry 有 plugin tag（除非天然跨 plugin）**
- 期望：`distillation-log.jsonl` 每行含 `"plugin": "..."`；`plugin-installs.jsonl` 含 `"plugin": "..."`；`sessions/*.md` 不强制（session 跨 plugin）。

**F-048 — jq 过滤可用**
- 验证：`jq 'select(.plugin=="development")' history/distillation-log.jsonl` 返回非空。

**F-049 — Append-only**
- 期望：history 文件不被 truncate / rewrite；轮换时通过 rotate-and-archive。

#### F.5 Queue / Locks / HITL-queue（§3.2.6）

**F-050 — Queue entry 含 plugin 字段**

**F-051 — Dashboard 跨 plugin 分组渲染**
- 期望：CLI（如有 `init.sh --status`）按 plugin 分组打印。

**F-052 — Locks 以路径键隔离 target_dir**
- 前置：两任务、两个不同 target_dir、同名相对路径。
- 期望：不互相阻塞（key=绝对路径而非相对）。

→ 设计依据：架构文档 §3.2、§3.2.2、§3.2.3、§3.2.4、§3.2.5、§3.2.6

---

### G. Task + target_dir （§8）

**G-001 — target_dir 必须为绝对路径**
- 反例：`./relative/path` → 拒绝。

**G-002 — target_dir 必须存在且为目录**
- 反例：不存在路径 → 拒绝；指向文件 → 拒绝。

**G-003 — target_dir 不能位于 `.codenook/` 内**
- 反例：`<workspace>/.codenook/something` → 拒绝。

**G-004 — target_dir 必须可读+可写**
- 反例：只读目录 → 拒绝。

**G-005 — Plugin 标志文件强制（按 plugin 声明）**
- 前置：plugin 声明 `requires_marker: pyproject.toml`。
- 期望：target_dir 缺该文件 → 拒绝。

**G-006 — `data_layout: workspace` 不要求 target_dir**
- 期望：任务创建时 target_dir 字段可缺省。

**G-007 — `data_layout: none` 同上且禁止设置 target_dir**

**G-008 — task.plugin 不可变**
- 步骤：手工改 state.json.plugin。
- 期望：下一次 OT 检测哈希不一致 → 标记 task tampered，blocked。

**G-009 — task.target_dir 不可变**
- 同上。

**G-010 — 子任务继承 plugin/plugin_version/target_dir**
- 期望：子任务 state.json 与父一致。

**G-011 — Sub-agent dispatch payload 含绝对 target_dir**
- 工具：抓 dispatch trace。

**G-012 — Sub-agent 不 cd 离开 target_dir**
- 工具：审计 sub-agent 进程的 cwd 切换。
- 期望：cwd 始终在 target_dir 子树内（manifest/state 写到 `.codenook/` 仍可，但通过绝对路径，不通过 cd）。

**G-013 — Cross-target 锁不冲突（关联 F-052）**

**G-014 — Plugin_version 创建时捕获，安装新版本不影响进行中任务**
- 步骤：创建 T-007 (dev v0.1) → in_progress → install dev v0.2 --force → tick T-007。
- 期望：T-007 仍按 v0.1 推进；新建 T-008 才用 v0.2。

**G-015 — 任务状态 plugin_missing**
- 步骤：创建 T-007 (writing) → 卸载 writing。
- 期望：tick 标记 plugin_missing；不崩溃；提供 reinstall hint。

**G-016 — E2E：单 workspace 多 target_dir 多 plugin 同时跑**
- 期望：3 个任务（dev → /repo-A，dev → /repo-B，writing → workspace 内）并行；queue / locks / hitl 互不污染。

→ 设计依据：架构文档 §8、§8.1、§8.2、§8.3

---

### H. v5 → v6 迁移（§9）

**H-001 — v5 e2e 剧本在 v6 上跑通**（历史 — v5 源码已于 v0.11.1 移除）
- 输入：`skills/codenook-v5-poc/reports/e2e-development-20260418-091543.md` 中描述的输入序列（archive only — 路径已不存在）。
- 期望：v6 + development plugin 产出等价的 phase artifacts；最终任务状态=ship。

**H-002 — 旧 codenook-core.md 不再被 MS 加载（文件审计）**
- 前置：v6 workspace。
- 工具：审计 MS 进程 open 调用。
- 期望：MS 不打开任何带 `codenook-core` / 旧 phase route 表 的文件；只打开 `core/shell.md`。

**H-003 — 路由表从 core 中消失**
- 测：`grep -r "phase routing table" .codenook/core/` 应无结果。

**H-004 — 不再有 `~/.codenook/` 引用**
- 测：`grep -rE "~/\.codenook|\$HOME/\.codenook" .codenook/` 应无结果。

**H-005 — Generic plugin 始终被 seed**
- 期望：`init.sh` 后无须任何额外步骤即可触发 generic fallback（B-005 联动）。

→ 设计依据：架构文档 §9、§3.1.1、§3.1.6

---

### M. 模型路由与探测 （§3.2.4.1 + §3.2.4.2）

> 覆盖 5 层模型解析链、Router 模型例外、`task-config-set` 自然语言入口、`model-probe` 探测 + 30 天 TTL、`tier_strong/balanced/cheap` 三档符号、`config-resolve` 输出 `_provenance` 回溯链。所有用例默认使用 §3 给出的 `mock-model-catalog` fixture（避免依赖真实运行时 API）。

#### M.1 model-probe（§3.2.4.2）

**M-001 — 运行时 API 探测**
- 前置：mock 一个 `claude-code` 风格 `list_models()` 返回 `[opus-4.7, sonnet-4.6, haiku-4.5]`。
- 步骤：跑 `init.sh --refresh-models`。
- 期望：`state.json.model_catalog.runtime == "claude-code"`；`available[]` 含 3 项；`resolved_tiers.{strong,balanced,cheap}` 三档全部解析。

**M-002 — env var 覆盖（运行时 API 不可用时）**
- 前置：模拟 runtime API 失败；设 `CODENOOK_AVAILABLE_MODELS=opus-4.7,gpt-5.4-mini`。
- 步骤：`init.sh --refresh-models`。
- 期望：catalog `available` 仅含 2 项；`resolved_tiers.strong=opus-4.7`；`balanced` 与 `cheap` 各按优先级解析（可能落到 gpt-5.4-mini 或为 null）。

**M-003 — catalog 写入字段完整**
- 期望：`state.json.model_catalog` 含 `refreshed_at` / `ttl_days=30` / `runtime` / `available[]`（每项有 `id`/`tier`/`cost`/`provider`）/ `resolved_tiers` / `tier_priority`。

**M-004 — TTL 触发自动刷新**
- 前置：`refreshed_at = now - 31d`。
- 步骤：随便跑一次需要 catalog 的操作（如 `config-resolve`）。
- 期望：`model-probe` 自动触发；`refreshed_at` 更新到 `now`；`history/config-changes.jsonl` 不必产生 entry，但 `history/orchestrator-log.jsonl` 应有 `event=model_probe_auto_refresh`。

**M-005 — `--refresh-models` / "刷新模型" 主动触发**
- 步骤：(a) `init.sh --refresh-models`；(b) MS 接收"刷新模型"自然语言。
- 期望：两条路径都 dispatch `model-probe` builtin skill；catalog `refreshed_at` 更新；MS 回 ≤200 字 confirm（含三档当前解析值）。

#### M.2 tier 解析（§3.2.4.2 step 5）

**M-006 — `tier_strong` 命中第一可用**
- 前置：catalog `tier_priority.strong=[opus-4.7, gpt-5.4]`，`available` 含两者。
- 步骤：plugin `config-defaults.yaml` 写 `models.planner=tier_strong`；调 `config-resolve`。
- 期望：effective `models.planner == "opus-4.7"`；`_provenance.symbol="tier_strong"`；`resolved_via="model_catalog.resolved_tiers.strong"`。

**M-007 — tier fallback（首选不可用顺位降级）**
- 前置：`tier_priority.strong=[opus-4.7, gpt-5.4]`；catalog `available` 仅含 `gpt-5.4`。
- 步骤：同 M-006。
- 期望：解析为 `gpt-5.4`；`resolved_tiers.strong="gpt-5.4"`。

**M-008 — unknown tier 符号回退（决议 #43，已与实现一致）**
- 步骤：plugin 写 `models.reviewer=tier_super_strong`；调 `config-resolve plugin=development`。
- 期望：**不抛错**；stderr 含 warning（提及合法 tier 列表 `[strong, balanced, cheap]`）；effective `models.reviewer` 等于 `model_catalog.resolved_tiers.strong`；`_provenance.symbol="tier_super_strong"`，`_provenance.resolved_via="fallback:tier_strong"`，`_provenance.from_layer` 与原写入层一致。
- 备注：原 M-008 期望"抛 `UnknownTier`"；M1 TDD 落地时与用户确认采用"warn + fallback `tier_strong`"以保持与字面值不在 catalog 时的口径一致；本用例已据此重写并归档为决议 #43。

**M-009 — `tier_priority` 用户覆盖**
- 步骤：`config.yaml.models.tier_priority.strong=[gpt-5.4, opus-4.7]`（颠倒）；catalog 含两者；`init.sh --refresh-models`。
- 期望：`resolved_tiers.strong=="gpt-5.4"`（用户 priority 胜出 builtin）。

**M-010 — 字面值与符号混用**
- 步骤：plugin `models.reviewer=gpt-5.4`（字面）+ `models.planner=tier_strong`（符号）。
- 期望：reviewer 直接采用 `gpt-5.4`（`_provenance.symbol=null`，`resolved_via="literal"`）；planner 走 tier 解析。若 `gpt-5.4` 不在 catalog → 打 warning 并回退到 `tier_strong`，`resolved_via="fallback:tier_strong"`。

#### M.3 5 层模型解析链（§3.2.4.1）

**M-011 — Layer 0 兜底**
- 前置：plugin 没有 `config-defaults.yaml.models`；config.yaml 无 `defaults.models` 与 plugin overrides；task 无 override。
- 期望：所有 role 落到 builtin `models.default=tier_strong`；`_provenance.from_layer=0`。

**M-012 — Layer 1 plugin baseline 覆盖 Layer 0**
- 前置：plugin `config-defaults.yaml.models.reviewer=tier_balanced`。
- 期望：reviewer 解析为 balanced 档；`_provenance.from_layer=1`，其他 role 仍为 layer 0。

**M-013 — Layer 2 workspace defaults 覆盖 Layer 1**
- 前置：M-012 + `config.yaml.defaults.models.reviewer=tier_cheap`。
- 期望：reviewer 解析为 cheap 档；`_provenance.from_layer=2`。

**M-014 — Layer 3 plugin overrides 覆盖 Layer 2**
- 前置：M-013 + `config.yaml.plugins.development.overrides.models.reviewer=tier_strong`。
- 期望：reviewer 解析为 strong 档；`_provenance.from_layer=3`。

**M-015 — Layer 4 task overrides 覆盖 Layer 3**
- 前置：M-014 + `tasks/T-007/state.json.config_overrides.models.reviewer=tier_balanced`。
- 步骤：`config-resolve plugin=development task=T-007`。
- 期望：reviewer 解析为 balanced；`_provenance.from_layer=4`；同任务的其他 role 仍按低层解析。

#### M.4 Router 模型例外（§3.2.4.1）

**M-016 — Router 不读 plugin 配置**
- 前置：plugin `config-defaults.yaml.models.router=tier_cheap`（伪造）；config.yaml 无 router 设置。
- 步骤：解析 router agent 模型。
- 期望：解析为 `tier_strong`（Layer 0 默认）；plugin 的 `models.router` 被忽略；`_provenance.from_layer=0`。

**M-017 — Router 默认 `tier_strong`**
- 前置：mock catalog `resolved_tiers.strong=opus-4.7`。
- 期望：router agent dispatch 时实际模型 = `opus-4.7`。

**M-018 — 用户 config 降档生效**
- 前置：`config.yaml.defaults.models.router=tier_cheap`。
- 期望：router 实际模型 = `resolved_tiers.cheap`；`_provenance.from_layer=2`，`symbol=tier_cheap`。

#### M.5 task-config-set（§3.2.4.1 决议 #38）

**M-019 — 自然语言"T-007 用 X" → state.json 写入**
- 步骤：MS 接收"T-007 的 reviewer 用最便宜的"。
- 期望：MS dispatch builtin skill `task-config-set` mode=set；`tasks/T-007/state.json.config_overrides.models.reviewer=tier_cheap`；`history/config-changes.jsonl` 追加 `{actor:user, scope:task, task:T-007, path:"models.reviewer", new:"tier_cheap"}`；MS 回 ≤200 字 confirm。

**M-020 — get 返回 provenance**
- 步骤：M-019 之后，"T-007 现在 reviewer 用什么模型？"。
- 期望：MS dispatch `task-config-set` mode=get；返回 effective literal id + 完整 `_provenance` 链（含 `from_layer=4 / symbol=tier_cheap / resolved_via=model_catalog.resolved_tiers.cheap`）；MS 把链翻译成 ≤200 字回答。

**M-021 — unset / 删除 override**
- 步骤：MS 接收"T-007 reviewer 改回默认"。
- 期望：dispatch `task-config-set` mode=unset；`config_overrides.models.reviewer` 被删除；后续 `config-resolve` 落回到上一层；history 追加 `{actor:user, new:null}`。

**M-022 — history 记录完备**
- 前置：连续做 set / set / unset 三步。
- 期望：`history/config-changes.jsonl` 三行；每行含 `ts / actor / scope / task / path / old / new`；时间戳单调递增。

#### M.6 `_provenance` 字段（§3.2.4.2 决议 #42）

**M-023 — provenance 含必填字段**
- 期望：`config-resolve` 返回的 `_provenance["models.<role>"]` 必含 `value` / `from_layer` / `symbol` / `resolved_via` 四字段；类型分别为 string / int(0..4) / string\|null / string。

**M-024 — 多层覆盖时层号正确**
- 前置：同时在 layer 1/3/4 写 reviewer。
- 期望：`from_layer=4`（最高）；`symbol` 反映 layer 4 写的符号（不是中间层）。

**M-025 — Catalog 缺失时 provenance 标记 fallback**
- 前置：`state.json.model_catalog` 不存在（极端兜底路径）。
- 步骤：`config-resolve plugin=development`。
- 期望：所有 model 字段 `value="opus-4.7"`（硬编码兜底）；`resolved_via="fallback:hardcoded"`；同时 stderr 打 warning。

**M-026 — `model-probe` 无 `--catalog` 时读写 state.json.model_catalog（M1.5 deferred）**
- 状态：**deferred to M1.5**；M1 测试默认显式传 `--catalog`，本用例验证默认位置解析与自动写回。
- 前置：mock workspace 有 `.codenook/`；环境变量 `CODENOOK_WORKSPACE` 设为该 workspace 根；`state.json` 存在但无 `model_catalog` 字段。
- 步骤：(a) 不传 `--catalog`，跑 `model-probe`；(b) 进入 workspace 子目录，仍不传 `--catalog`，再跑一次。
- 期望：(a) `<workspace>/.codenook/state.json.model_catalog` 被写入（`refreshed_at / runtime / available[] / resolved_tiers`）；(b) 通过 cwd 向上搜索定位到同一 workspace；catalog 命中后不重复探测（除非 TTL 过期）。
- 反例：清掉 `CODENOOK_WORKSPACE` 且 cwd 不在任何 `.codenook/` 子树下 → stderr warning `"no workspace catalog; using hardcoded fallback"`，且**不**写盘。
- 与 `--catalog` 显式路径对比：显式路径 `model-probe --catalog ./fixtures/cat.json` 读后**不**触发自动写回，避免污染只读 fixture。

→ 设计依据：架构文档 §3.2.4.1、§3.2.4.2、§12 决议 #36–#42

---

## 3. 测试数据准备

### 3.1 Fixture plugin 包目录结构

所有 fixture 维护在仓库 `tests/fixtures/plugins/` 下，每个一个目录，配套 `Makefile` 目标 `make fixtures` 把每个目录 tar.gz 化到 `tests/_build/`。

```
tests/fixtures/plugins/
├── good/                              # 通过 12 gates + 安全扫描的最小 plugin
│   ├── plugin.yaml                    # name=good, version=0.1.0, summary, keywords...
│   ├── phases.yaml                    # 1 phase: clarify
│   ├── transitions.yaml               # clarify.clarifier.ok → complete
│   ├── entry-questions.yaml           # creation: required: [title, summary]
│   ├── hitl-gates.yaml                # gates: {}
│   ├── roles/clarifier.md
│   ├── README.md
│   └── CHANGELOG.md
│
├── good-development/                  # 完整 dev plugin（H-001 用）
│   └── ... (8 phases)
│
├── good-writing/                      # writing plugin（多 plugin 共存用）
│
├── bad-symlink/                       # E-041
│   └── roles/clarifier.md -> /etc/passwd
│
├── bad-traversal/                     # E-044
│   └── plugin.yaml (data_glob: ["../../*"])
│
├── bad-shebang/                       # E-048
│   └── skills/x/run.pl  ('#!/usr/bin/perl')
│
├── bad-secret/                        # E-051
│   └── roles/clarifier.md (含 AKIA... 字串)
│
├── bad-keyword/                       # E-049
│   └── skills/x/run.sh ('curl ... | sh')
│
├── bad-missing-summary/               # E-023
├── bad-name-uppercase/                # E-027
├── bad-core-version/                  # E-028
├── bad-orphan-phase/                  # E-033
├── bad-reserved-name/                 # E-037 (name: core)
├── bad-too-large/                     # E-039 (>10MB padding)
└── bad-hidden-env/                    # E-042 (.env)
```

**每个 fixture 目录必须包含 `EXPECT.txt`**：声明预期失败 gate 编号，便于自动化对账。

### 3.2 Mock workspace 模板

`tests/fixtures/workspaces/`：

- `empty/` — 仅 `init.sh` 运行后的 baseline（含 generic）。
- `dev-only/` — empty + dev plugin 已装，1 个 in_progress task（phase=design）。
- `multi-plugin/` — empty + dev + writing + 自定义 ops；3 个任务跨 plugin。
- `corrupted-state/` — state.json 损坏（D-012 用）。
- `with-archived-memory/` — 已卸载过的 plugin，验证归档存在（E-062 用）。

### 3.3 Mock LLM stub

- 实现：`tests/stubs/llm-stub.py`，接受标准 dispatch payload，按 `responses/<agent>/<scenario>.json` 返回固定 verdict。
- 调度：通过环境变量 `CODENOOK_LLM_BACKEND=stub` 启用；CI L1/L2 默认走 stub。
- 真 LLM：仅 L3 + nightly 跑。

### 3.4 共存工作区快照

`tests/snapshots/multi-plugin-active.tar.gz`：
- dev 任务 T-001 phase=test，writing 任务 T-002 phase=draft 等待 HITL，generic 任务 T-003 in clarify。
- queue 含 3 entry，hitl-queue 含 1 entry。
- history 已 rotate 1 次。

### 3.5 Mock model catalog fixture（M 子系统专用）

`tests/fixtures/model-catalog/`：

```
mock-default.json         # 三档全可用，对应 §3.2.4.2 文档样例
mock-only-cheap.json      # 仅 haiku/gpt-mini 可用（M-007 fallback 用）
mock-empty.json           # available=[]（M-025 极端兜底）
mock-corrupted.json       # 非法 JSON（R-27 用）
mock-cycle.json           # tier_priority 循环引用（R-28 用，例如自定义新 tier 指向自身）
```

**`mock-default.json` 示例**：

```json
{
  "refreshed_at": "2026-04-18T09:15:43Z",
  "ttl_days": 30,
  "runtime": "mock",
  "available": [
    {"id": "opus-4.7",   "tier": "strong",   "cost": "high", "provider": "anthropic"},
    {"id": "sonnet-4.6", "tier": "balanced", "cost": "mid",  "provider": "anthropic"},
    {"id": "haiku-4.5",  "tier": "cheap",    "cost": "low",  "provider": "anthropic"},
    {"id": "gpt-5.4",    "tier": "balanced", "cost": "mid",  "provider": "openai"}
  ],
  "resolved_tiers": {"strong": "opus-4.7", "balanced": "sonnet-4.6", "cheap": "haiku-4.5"},
  "tier_priority": {
    "strong":   ["opus-4.7", "opus-4.6", "sonnet-4.6", "gpt-5.4"],
    "balanced": ["sonnet-4.6", "sonnet-4.5", "gpt-5.4", "gpt-5.4-mini"],
    "cheap":    ["haiku-4.5", "gpt-5.4-mini", "gpt-4.1", "sonnet-4.5"]
  }
}
```

**注入方式**：测试脚本通过 `cp tests/fixtures/model-catalog/<x>.json $WS/.codenook/state.json.model_catalog.fragment` 后调 helper `merge_catalog_fragment`，或直接覆盖 `state.json` 的 `model_catalog` key（用 `jq`）。

→ 设计依据：架构文档 §5、§7、§7.4、§3.2、§3.2.4.1、§3.2.4.2

---

## 4. 自动化策略

### 4.1 工具与运行模型

| 用例类型 | 自动化方式 | 备注 |
|---|---|---|
| Bash + 文件断言（init.sh、安装、解析、文件审计） | bats-core | 占总用例 ~70% |
| YAML / JSON schema 校验 | yq + jq + python-jsonschema | gate 7/8/9 / config schema |
| Sub-process fs 审计 | macOS: `fs_usage`；Linux: `strace -e openat,write` | A-007/A-008/D-008/F-038 |
| 安全扫描规则（E-041..E-052） | bats + 预制 fixture（每条规则一个）| 规则添加时强制新增用例 |
| LLM 决策（router、tick、distiller） | mock LLM stub（默认）+ 真 LLM nightly（少数关键剧本） | 真 LLM 用 GPT-5-mini 控成本 |
| E2E（H-001 等） | shell 驱动脚本 + artifact diff 工具（`diff -r --ignore-matching-lines='ts:'`） | 时间戳 / 哈希字段需 normalize |

### 4.2 Mock LLM 还是真 LLM？

| 用例 | 推荐 |
|---|---|
| Router schema / 字段一致性 / disabled plugin 跳过 | mock |
| Router 实际分类正确性（B-003/B-004/B-005/B-006） | 双跑：mock（确定）+ 真（漂移容忍：3 选 2） |
| OT 单跳算法（C-001..C-020） | mock |
| OT 多跳序列（C-021..C-030） | mock |
| Distiller 内容质量 | 真 LLM nightly |
| H-001 完整 e2e | 真 LLM nightly + mock 快速 smoke |

漂移容忍：真 LLM 用例同条 prompt 重跑 3 次，多数票判定通过；记录每次原始返回到 `tests/_artifacts/`。

### 4.3 CI 集成

- **PR check（必跑）**：L1 全量 + L2 全量 + L3 mock 模式 smoke（H-001 mock 版）。
- **Nightly**：L3 真 LLM 全量（H-001 / B-017 / E-061 / G-016）。
- **手动**：性能基准（5.x metrics）。
- **失败保留**：CI artifact 上传 staging 目录、history tail、tick trace（见 §5）。
- **门禁**：L1/L2 100% 通过；L3 mock 100% 通过；L3 真 LLM 允许≤1 个 known-flaky（必须 issue tracked）。

### 4.4 测试隔离

每个用例：
- 独立的 `<workspace>` 临时目录（用 `mktemp -d` 在仓库内 `tests/_tmp/` 下创建——**不**用 `/tmp`）。
- 每用例后清理；失败则按 `KEEP_TMP=1` 保留供调试。

→ 设计依据：架构文档 §3.1.5、§7.4、§4

---

## 5. 可观测性与诊断

### 5.1 失败时 dump 清单（CI artifact 自动收集）

每用例失败时，收集并打包：

1. **Staging 目录**（如安装失败）：`.codenook/staging/<rand>/` 全量。
2. **history tail**：每个 jsonl 末尾 200 行。
3. **state 快照**：`state.json` + `tasks/*/state.json`。
4. **Tick trace**：`history/orchestrator-log.jsonl` 全量（带 task_id 过滤）。
5. **Dispatch trace**（开发期开启）：`history/dispatch-trace.jsonl`。
6. **Router decisions**：`history/router-decisions.jsonl`。
7. **Security report**（如有）：`staging/<rand>/security-report.md`。
8. **fs_usage / strace 输出**（如该用例使用 fs 审计）。
9. **LLM stub 调用日志**（mock 模式）：每次请求 + 响应。
10. **Tmp workspace 全量 tar.gz**（用例所用临时目录）。

提供 helper：`tests/lib/dump-on-fail.sh <workspace> <test-name>`。

### 5.2 关键 metrics

| Metric | 测量点 | 期望 / 红线 |
|---|---|---|
| MS context token usage（稳态） | A-011；用 LLM provider 返回的 usage 字段 | ≤ 5K input prompt（不含对话历史） |
| shell.md 字节数 | E2E 启动阶段 | ≤ 3072 |
| SR 摘要字符数 | D-003 | ≤ 500 |
| OT 单跳耗时 | OT helper agent end-to-end wall time | p50 ≤ 5s（mock）；p95 ≤ 30s（真 LLM） |
| OT summary token 数 | A-006/C-018 | ≤ 200 字 |
| Plugin 安装总耗时 | E-001 wall time | p50 ≤ 3s；p95 ≤ 10s（不含网络） |
| Catalog 体积 | B-011 | ≤ 8KB |
| Router decision 耗时 | B-003 wall time | p95 ≤ 5s |

每条 metric 写入 `tests/_metrics/<date>.jsonl`，nightly 与基线对比；超过红线发警报。

### 5.3 Doctor 子命令的测试覆盖

- 测试 `init.sh --doctor`（如设计提供）输出：检测损坏 plugin、缺失 generic、孤儿 staging、超大 history。
- 用例：每种损坏 fixture 各一条断言。

→ 设计依据：架构文档 §3.1.5、§7.3、§7.4.2

---

## 6. 风险测试矩阵

| 风险编号 | 攻击 / 故障面 | 触发方式 | 期望防御层 | 主要用例 |
|---|---|---|---|---|
| **R-01** | 恶意 plugin 包（symlink） | 用户从不可信 URL 安装 | §7.4.1 安全扫描 → gate 10 | E-041 |
| **R-02** | 路径穿越（plugin.yaml 字段） | manifest data_glob 含 `../` | §7.4 gate 12 + §7.4.1 manifest 合理性 | E-044, E-045, B-014 |
| **R-03** | 路径穿越（router 注入） | manifest examples 含路径字串 | router 不解引用；仅作分类语料 | B-013 |
| **R-04** | Secret 泄露（plugin 内嵌） | plugin 文件含 AWS key | §7.4.1 secret-scan | E-051, E-052 |
| **R-05** | Secret 泄露（运行时混入 history） | sub-agent 把 env 写日志 | secrets-resolve 仅注 env，不入上下文；history grep | F-037 |
| **R-06** | Secret 进 git | 用户编辑 secrets.yaml 后 commit | `.gitignore` + pre-commit hook | F-035 |
| **R-07** | 误删用户 memory（卸载） | `--remove-plugin <p>` | 归档到 `memory/.archived/` 而非删除 | E-062 |
| **R-08** | 误删用户 overrides（升级） | `--force` 升级 | 仅覆盖 plugins/<p>/，保留 overrides/memory | E-061 |
| **R-09** | Config 静默失效 | 用户写未知 key | config-validate 强校验 | F-032, F-033 |
| **R-10** | Main session 被偷塞内容 | plugin manifest 中夹长字串 | router catalog 仅取声明字段；MS 不读 plugin 文件 | A-007, B-011, B-013 |
| **R-11** | Main session 上下文爆炸 | 用户长对话 / 多任务 | shell.md ≤3K + SR ≤500 + tick ≤200 | A-011, A-012, D-003, C-018 |
| **R-12** | 命令注入（shebang） | plugin 自带 perl 脚本 | shebang 白名单 | E-048 |
| **R-13** | 命令注入（关键字） | plugin 含 curl…\|sh | 关键字扫描 | E-049, E-050 |
| **R-14** | 越权可执行文件 | plugin 在 roles/ 放 +x 脚本 | 权限规则 | E-046, E-047 |
| **R-15** | 任务级污染（state.plugin 篡改） | 用户改 state.json | OT 检测一致性 → blocked | G-008, G-009 |
| **R-16** | Plugin 卸载后任务失活 | 卸 active plugin | tick 标记 plugin_missing；不崩溃 | E-063, G-015 |
| **R-17** | 名字保留冲突 | plugin name=core | gate 11 | E-037, E-038 |
| **R-18** | 拒绝服务（巨包） | 安装 GB 级 tarball | gate 12 size 限制 | E-039 |
| **R-19** | Router 决策被劫持 | LLM 返回任意 plugin 但 rationale 与任务无关 | rationale 暴露给用户；user_override 可推翻；记录 | B-015 |
| **R-20** | 跨 plugin 知识泄露 | dev 蒸馏的 prod 部署知识被 writing 任务读到 | 三层 memory 严格隔离 | F-004, F-016 |
| **R-21** | HITL 绕过 | gate 配置 auto_approve_if 表达式注入 | schema 校验 + 安全表达式语法 | C-007, E-035 |
| **R-22** | Sub-agent 越界 cwd | agent cd 到 target_dir 外 | dispatch 协议规定；可观测 | G-012 |
| **R-23** | Tick 重复派发（重入）| 并发触发 tick | 无状态算法 + lock | C-015 |
| **R-24** | History 被改写 | 用户/agent 试图 truncate | append-only 校验 | F-049 |
| **R-25** | Secrets 通过 LLM 出网 | sub-agent 把 secret 拼到 prompt | secrets-resolve 仅 env，不进 prompt；agent profile 强约束；可加 outbound prompt 扫描 | F-036, F-037 |
| **R-26** | Catalog 中无 `tier_strong` 任何候选 | 运行时 API 返回空 / 用户自定义 priority 全部不可用 | tier 解析顺位降级 strong→balanced→cheap；全空兜底硬编码 `opus-4.7` + warning | M-007, M-025 |
| **R-27** | `state.json.model_catalog` 损坏 | 文件被截断 / 非法 JSON | `model-probe` 重跑 + warning；`config-resolve` 用硬编码 fallback 不 crash | M-025 + 新增 M-fixture `mock-corrupted.json` |
| **R-28** | `tier_priority` 符号循环引用 / 自定义新 tier 未解析 | 用户在 `config.yaml.models.tier_priority` 写 `tier_x: [tier_y]` 互指 | `config-resolve` 检测 → `UnknownTier` 报错；不允许 priority 内嵌符号（只接受字面 model id） | M-008 + M-fixture `mock-cycle.json` |

→ 设计依据：架构文档 §3.1.7、§3.2.4、§7.4.1、§8.2

---

## 7. 已识别的可测试性歧义（反馈给设计文档）

> **状态更新（2026-04-18）**：以下 13 条原歧义已全部被架构文档 §12 的落地反馈决议（#T-1..#T-13、#I-1..#I-10）解决；#36–#42 进一步覆盖模型路由领域。**M1 TDD 落地反馈（2026-04-18 追加）**：另有 3 条边缘歧义在 M1 实现期间被识别并归档为决议 **#43 / #44 / #45**（未知 tier 回退、Layer 0 publish `models.router`、顶层 key 白名单），见下方追加段。逐条标注 ✅ + 解决出处。

1. ✅ **§3.1.3 OT 触发频率** — 由 #T-1 解决：默认 focus task 1 次/回合；"全部继续"按 active_tasks fan-out。
2. ✅ **§3.1.4 SR 实现技术栈** — 由 #T-2 解决：MVP 为确定性脚本（无 LLM），未来可升级，token ≤500。
3. ✅ **§3.1.7 dispatch payload 长度上限** — 由 #T-3 解决：硬上限 500 字，推荐 ≤200，超出落盘传路径。
4. ✅ **§3.2.4 `merge: replace` 语法** — 由 #T-4 解决：schema 注解 `merge: replace|deep|append`，默认按字段类型推断。
5. ✅ **§3.2.4 自动 mutator 写入并发** — 由 #T-5 解决：fs advisory lock + `_version` 乐观并发，最多 retry 3 次。
6. ✅ **§7.2 `--remove-plugin` 与 active task** — 由 #T-6 解决：默认阻止 active task；`--force-orphan` 标记 orphaned 后允许卸载。
7. ✅ **§7.4 错误码命名** — 由 #T-7 解决：固化为 `G01..G12`，报错前缀 `[Gxx]`。
8. ✅ **§7.4.1 `--allow-warnings` 范围** — 由 #T-8 解决：仅降级 warning（权限/BOM/CRLF/杂项）；critical（symlink/穿越/secret/关键词/shebang）始终拒绝。
9. ✅ **§8.2 `target_dir` 不可变 / rename** — 由 #T-9 解决：`state.json.target_status: ok|target_missing|tampered`，OT 在 tick 开头检测。
10. ✅ **§3.2.6 HITL queue 文件命名** — 由 #T-10 解决：`<plugin>--<task>--<gate>--<ts>.json`。
11. ✅ **§3.1.5 "对话历史" 是否计入 5K** — 由 #T-11 解决：5K 红线只算固定上下文（shell + resume + tick 摘要）；对话历史独立累积，main session 不自我 distill。
12. ✅ **Router confidence_threshold 默认值** — 由 #T-12 解决：`< threshold` 严格小于触发 ask_user；等于阈值视为通过。
13. ✅ **§9 v5→v6 e2e 通过判据** — 由 #T-13 解决：语义等价（phase 数 + verdict 序列 + 关键 state.json 字段），不要求 byte-level diff。

**模型路由领域（#36–#42）落地后未发现新歧义**：5 层链 / Router 例外 / `task-config-set` / `model-probe` / 三档符号 / `tier_priority` / 30 天 TTL / `_provenance` 字段语义在架构 §3.2.4.1 + §3.2.4.2 已给出可判定的伪代码与字段 schema，M-001..M-025 全部可机械化验证。

**M1 TDD 追加决议（#43 / #44 / #45）**：
- ✅ **#43**（架构 §3.2.4.2）未知 tier 符号 → warn + fallback `tier_strong`；M-008 已据此重写。
- ✅ **#44**（架构 §3.2.4.1 / §3.2.4.2）Layer 0 同时发布 `models.default` 与 `models.router`；M-016 据此可机械化验证 plugin 写的 router 值被忽略。
- ✅ **#45**（架构 §3.2.4）`config.yaml` 顶层 key 白名单固化为 10 项；F-032 已据此重写。
- 新增用例：F-053（M5 deferred）schema-driven merge；M-026（M1.5 deferred）`model-probe` 无 `--catalog` 时读写 `state.json.model_catalog` + 自动写回。

→ 设计依据：架构文档 §12（决议 #I-1..#I-10、#T-1..#T-13、#36..#42）

---

## 附录 A — 用例索引

- A 子系统：A-001..A-014（14 例）
- B 子系统：B-001..B-017（17 例）
- C 子系统：C-001..C-030（30 例）
- D 子系统：D-001..D-012（12 例）
- E 子系统：E-001..E-012, E-021..E-040, E-041..E-055, E-061..E-065（57 例）
- F 子系统：F-001..F-052 + F-053（M5 deferred）（53 例）
- G 子系统：G-001..G-016（16 例）
- H 子系统：H-001..H-005（5 例）
- **M 子系统：M-001..M-025 + M-026（M1.5 deferred）（26 例）**
- 风险矩阵：R-01..R-28（28 项，引用上述用例）

**用例总数：14 + 17 + 30 + 12 + 57 + 53 + 16 + 5 + 26 = 230**

→ 设计依据：架构文档 §2–§9

---

*本测试计划与架构文档 `architecture.md` 同步演进。任何架构条款改动应反向触发本文档的用例审查。*

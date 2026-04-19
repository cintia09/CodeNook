# CodeNook v6 — Task Chains（任务链：父子链接 + 链感知上下文）

> **Status**: Draft (M10.0). 本文是 M10 全系列里程碑（M10.0–M10.7）的规范来源。
> M10 在 M9 memory 层与 conversational router-agent 之上引入**任务父子链接**
> 机制：新任务在创建时通过相似度评分提示候选父任务；用户确认后，router-agent
> 自动沿祖先链 LLM 摘要、注入子任务的提示词。M10 是**对 M9 的纯增量扩展**：
> 不修改 memory 层语义、不改写 plugin 层、不引入新的可写存储路径，
> `parent_id` / `chain_root` 作为 task `state.json` 的可选字段共存。
>
> 配套交互式需求/验收文档将在 M10.0.1 测试用例文档中产出
> （`docs/v6/m10-test-cases.md`）。本文与之一一对应：每条 FR-CHAIN-XXX /
> AC-CHAIN-XXX / G-CHAIN-X 在本文中至少出现一次以阐明取舍。

---

## 1. Motivation

### 1.1 M9 留下的差距

M9 已交付 memory 层（`.codenook/memory/`）+ 三类抽取器（knowledge / skills /
config）+ MEMORY_INDEX 注入；router-agent 看见所有匹配 `applies_when` 的
memory 条目。但 M9 解决的是**「跨任务的常驻知识」**问题，没有解决以下三件事：

1. **同一意图族的父子上下文**：用户先做「实现 feature A」（任务 T-007），
   接着开「为 feature A 写测试」（任务 T-012）。T-012 与 T-007 高度相关，
   但 T-007 的 design.md / impl-plan.md / decisions.md 不会被自动抽取成
   memory 条目（它们是任务级中间产物，不是项目级常驻知识），结果 T-012
   的 router-agent 完全看不到 T-007 的产出，需要用户手工粘贴或者依赖
   memory 抽取器的「碰巧命中」。
2. **中间产物的检索代价**：任务工作目录 (`.codenook/tasks/<tid>/`) 中
   累积了 design / plan / test / decisions 等若干文件；要让子任务看到
   父任务的产出，最朴素的做法是把它们整体塞进子任务的 prompt，但单个
   父任务即可超出整个 router prompt 的 16K 预算（spec memory §11.2），
   更不用说沿祖先链聚合。
3. **「任务之间的因果关系」缺乏一等模型**：M4 的 `depends_on` 字段是
   tick 调度用的拓扑顺序，不携带「我是谁的延续」的语义；router-agent
   也不读取 `depends_on`。M10 为这层语义补一个独立的 `parent_id`。

### 1.2 M10 的目标（对应 G-CHAIN-1 … G-CHAIN-5）

| ID | 目标 | 验收来源 |
|---|---|---|
| G-CHAIN-1 | 新任务创建时，系统**自动**对开放任务做相似度排名并提示 top-3 | AC-CHAIN-SUG-* |
| G-CHAIN-2 | 用户可在创建时确认 / 改选 / 选择 "independent"；事后亦可 attach / detach | AC-CHAIN-LINK-* |
| G-CHAIN-3 | router-agent 自动沿祖先链聚合上下文，注入 `{{TASK_CHAIN}}` slot | AC-CHAIN-CTX-* |
| G-CHAIN-4 | 链聚合受 8K token 预算约束，超出由 LLM 二阶段压缩 | AC-CHAIN-BUD-* |
| G-CHAIN-5 | chain walk + 摘要全程 best-effort，失败不阻塞 router 渲染 | AC-CHAIN-NF-* |

### 1.3 设计原则（在所有取舍中胜出）

- **可选叠加**：`parent_id` 缺省为 `null`；M10 之前创建的任务零侵入。
- **CLI-first，无 UI**：`task-chain {attach|detach|show}` 子命令足以覆盖
  M10 全部交互；树状可视化不在范围。
- **不改 memory 语义**：M10 不向 `.codenook/memory/` 写任何东西，链摘要是
  **每次 spawn 时即用即弃**的提示词片段，落盘只为审计与缓存。
- **Best-effort，永不阻塞**：相似度服务、chain walk、摘要 LLM 任一环节
  失败 → `{{TASK_CHAIN}}` 渲染为空字符串 + 写 audit；router 继续工作。
- **最小新增依赖**：相似度算法用纯 Python token-set Jaccard（与 M9.6
  `match_entries_for_task` 同源思路），不引入 embedding / vector store。
- **Greenfield**：M10 是 v0.10 全新启动；旧任务在缺字段时直接被读为
  独立任务，无需任何转换脚本。

### 1.4 Non-goals

为了让 M10 在 8 个里程碑内闭环，下列议题**明确不在 M10 范围**：

- **不替换 memory 层**：链摘要不写入 `memory/`，不与 knowledge extractor
  竞争；memory 与 chain 是**正交**的两套上下文来源（前者是项目常驻、
  后者是任务谱系）。
- **不跨 workspace 链接**：`parent_id` 必须指向同一 `<workspace>/.codenook/tasks/`
  下存在的任务；跨仓库 / 跨 workspace 的「跨界引用」属于 M11+ 议题。
- **不做任务树可视化 UI**：M10 仅交付 CLI（`task-chain show <tid>` 输出
  child→root 的纯文本列表）；图形化 / Web UI 留给后续。
- **不引入 sibling 上下文**：默认只走祖先；兄弟任务（同 parent_id）不
  进入 router 提示。已在 §11 列为开放问题。
- **不重写 `depends_on`**：`depends_on` 仍由 tick 用作调度依赖图；
  `parent_id` 是独立的语义字段，二者可同时存在、互不蕴含。
- **不做循环修复**：检测到环 → `set_parent` 抛 `CycleError`；用户必须
  手动选择不同 parent，不会自动「打破链」。

---

## 2. Data Model

### 2.1 任务存储位置（M4–M9 已确立）

CodeNook v6 的任务持久化路径（**调研结论，不发明新结构**）：

```
<workspace>/.codenook/tasks/<task_id>/
├── state.json            # 主状态文件（JSON Schema：codenook-core/schemas/task-state.schema.json）
├── draft-config.yaml     # router-agent 起草的任务配置（M8.1）
├── router-context.md     # router-agent ↔ 用户多轮对话归档（M8.4）
├── router-reply.md       # 当前 turn 的回复（每次 spawn 覆盖；M8.4）
├── outputs/              # 任务产出（subagent 写入）
└── (可选) design.md / impl-plan.md / test.md / decisions.md
```

代码侧的真值来源：

- **schema**：`skills/codenook-core/schemas/task-state.schema.json`
- **写入方**：`skills/codenook-core/skills/builtin/orchestrator-tick/_tick.py`
  （`atomic_write_json_validated(... TASK_STATE_SCHEMA)`）
- **读入方**：`render_prompt.py`、`_tick.py`、`spawn.sh --confirm`
- **任务 ID 校验**：`_tick._check_task_id`（接受 `T-NNN`、`T-NNN.N`、
  `T-NNN-cN` 等当前格式，正则在该函数内）

### 2.2 现有 schema 摘录（与 M10 相关字段）

```jsonc
{
  "schema_version": 1,
  "task_id": "T-007",
  "plugin": "development",
  "phase": "implement",
  "status": "in_progress",
  "depends_on": ["T-005"],     // M4 调度依赖（拓扑用）
  "subtasks":   ["T-007-c1"],  // tick decompose 产生的子任务
  "history":    [...]
}
```

注意：`depends_on` 与 `subtasks` 是 tick 内部调度模型；两者都**不是**
M10 的「父子链接」概念。M10 的 `parent_id` 表达「我是谁的延续」语义，
独立于 tick 调度图。

### 2.3 M10 schema 增量

`schemas/task-state.schema.json` 新增**两个可选属性**（不变更 `required`
列表，旧 state.json 仍验证通过）：

```jsonc
{
  "parent_id":  { "type": ["string", "null"], "description": "User-confirmed parent task in the same workspace; null = independent." },
  "chain_root": { "type": ["string", "null"], "description": "Cached terminal ancestor of the chain (for O(1) root lookup); MUST equal walk_ancestors(...).last when parent_id != null, else null." }
}
```

字段约束：

| 字段 | 类型 | 默认 | 不变量 |
|---|---|---|---|
| `parent_id` | `string \| null` | `null` | (a) `parent_id != task_id`；(b) `parent_id` 必须指向同一 workspace 下已存在的 `state.json`；(c) `walk_ancestors(parent_id)` 不得包含 `task_id`（无环）；(d) 形式与 `_check_task_id` 一致。 |
| `chain_root` | `string \| null` | `null` | 当 `parent_id is null` 时必须为 `null`；当 `parent_id` 非 `null` 时等于沿父链走到尽头的最后一个 task_id（即唯一一个 `parent_id is null` 的祖先；若整条链上所有任务都有 parent，则发生不变量违反 → CycleError）。 |

### 2.4 任务 ID 格式

M10 不引入新 ID 格式，沿用 M4 现状：

- 主任务：`T-NNN`（如 `T-007`）
- tick decompose 子任务：`T-NNN-cN`（如 `T-007-c1`）
- v5 衍生形式：`T-NNN.N`（如 `T-007.1`）
- 校验由 `_tick._check_task_id` 统一执行；M10 的 `task_chain.set_parent`
  在落盘前**复用同一函数**校验 `parent_id`。

### 2.5 循环防止 (cycle prevention)

`set_parent(child, parent)` 必须满足：

1. `parent != child`（直接自环）
2. `child not in walk_ancestors(parent)`（间接环 / 跨多代环）
3. `parent` 对应的 `state.json` 存在且可读

若任一条件不满足 → 抛 `CycleError(reason)`，**不写盘**、**不更新
chain_root**，调用方自行处理（CLI 打印错误并退出非零）。

### 2.6 chain_root 为何缓存

`chain_root` 是 `walk_ancestors` 终点的物化缓存：

- **读路径热点**：router-agent 在每次 spawn 时调用 `chain_root()` 决定
  是否要走完整链；若链根尚未变更（snapshot 命中）则直接复用上次结果。
- **更新代价**：仅在 `set_parent` / `detach` 时重算，且只影响**当前
  任务及其祖先链**（不会传递到子代，因为子代各自缓存自身的 chain_root）。
- **不变量**：见 §2.3；任何写入路径都必须配对更新 `chain_root`，
  否则 §8 的 chain-snapshot 会判定为 stale 而强制重算。

---

## 3. Lifecycle

### 3.1 任务创建时的链建议流程

```
┌────────────────────────────────────────────────────────────────┐
│ user types: "为 feature/auth 写测试"                            │
│        │                                                       │
│        ▼                                                       │
│ main session → spawn router-agent (M8.4)                       │
│        │                                                       │
│        ▼                                                       │
│ render_prompt.py 在 prepare 阶段:                                │
│   1. 读 .codenook/tasks/ 下所有 status != done/cancelled 的任务   │
│   2. 调 parent_suggester.suggest_parents(ws, child_brief)       │
│   3. 取 score >= 0.15 的 top-3                                  │
│   4. 注入到 router-agent 的工具提示（不是 {{TASK_CHAIN}} slot,    │
│      而是辅助 router 提问的元信息）                                │
│        │                                                       │
│        ▼                                                       │
│ router-agent 在 router-reply.md 中向用户呈现:                    │
│   "我建议把这个任务挂在 T-007 'feature/auth' 下（相似度 0.42，    │
│    匹配 token: ['feature','auth','test']）。                      │
│    可选：[1] 挂 T-007 [2] 挂 T-005 [3] independent [4] 改选其它"  │
│        │                                                       │
│        ▼                                                       │
│ 用户回复 "1"                                                    │
│        │                                                       │
│        ▼                                                       │
│ next spawn (--confirm): freeze_to_state_json 时调用             │
│   task_chain.set_parent(ws, task_id, "T-007")                  │
│   → state.json 写入 parent_id="T-007", chain_root="T-005"       │
└────────────────────────────────────────────────────────────────┘
```

### 3.2 brief 的来源

`child_brief` 用于相似度比较的字符串，由 `render_prompt.py` 的
`_build_task_brief()`（M9.6 已存在）按以下顺序拼接：

1. 当前 spawn 的 `user_turn`（即用户最新一条输入）
2. `router-context.md` 中所有 `role: user` 的历史 turn 内容

这给 suggester **最大 token 集**而**零额外 LLM 成本**。M10 不重复实现
该函数，复用现有实现。

### 3.3 后期 attach / detach（CLI）

M10 不要求一切链接都在创建时确定；用户可在任务进行中显式调整：

```bash
# 把已存在的 child 挂到 parent 下（要求 child.parent_id 当前为 null）
python3 -m _lib.task_chain attach <child_id> <parent_id> [--workspace .]

# 解除 child 的父任务
python3 -m _lib.task_chain detach <child_id> [--workspace .]

# 显示 child 的祖先链（child→root）
python3 -m _lib.task_chain show <child_id> [--workspace .]
```

行为约定：

- `attach` 在 `child.parent_id` 已非空时**默认拒绝**（`AlreadyAttachedError`）；
  必须先 `detach` 再 `attach`，避免误覆盖。可加 `--force` 跳过该保护
  （仍执行 cycle check）。
- `detach` 是幂等的：对已 detach 的任务再次执行返回成功，不写盘。
- `show` 不修改任何文件，纯读路径，可作为 lint 工具使用。

### 3.4 chain walk 算法

```python
def walk_ancestors(workspace, task_id, *, max_depth=None, max_tokens=None):
    """child → root 顺序返回 task_id 列表（含自身）。

    max_depth: 安全阈值，默认 None = 无上限；推荐 router 路径设置
               一个保守值（spec §6 默认 100）防止数据损坏导致死循环
               时仍能终止。
    max_tokens: 估算 (∑ ancestor briefs) 超出该值后早停；返回的列表
                可能短于完整链。注入提示前由 chain_summarize 做二阶段
                压缩，所以 walk 本身不需要严格满足该上限。
    """
    seen = set()
    chain = []
    cur = task_id
    while cur is not None:
        if cur in seen:
            raise CycleError(f"cycle at {cur}")
        seen.add(cur)
        chain.append(cur)
        if max_depth is not None and len(chain) >= max_depth:
            break
        cur = get_parent(workspace, cur)
    return chain
```

终止条件：

1. `parent_id is None` → 自然终止（最常见）
2. `state.json` 不存在 / 损坏 → 终止并把当前累计链返回 + audit
   `chain_walk_truncated`（best-effort）
3. 检测到环 → `CycleError`（理论上 `set_parent` 已防住，这里是兜底）
4. `max_depth` 命中 → 提前终止 + audit `chain_walk_truncated`

### 3.5 chain_root 维护

写路径仅两处：

```python
def set_parent(ws, child, parent):
    _validate_child_id(child)
    _validate_parent_id(parent)         # 含 cycle check
    state = load_state(ws, child)
    state["parent_id"] = parent
    state["chain_root"] = _compute_root(ws, parent)   # 沿 parent 链走到底
    atomic_write_state(ws, child, state)
    _invalidate_snapshot(ws)
    audit(ws, asset_type="chain", outcome="chain_attached", verdict="ok",
          source_task=child, reason=f"parent={parent},root={state['chain_root']}")

def detach(ws, child):
    state = load_state(ws, child)
    if state.get("parent_id") is None:
        return
    state["parent_id"] = None
    state["chain_root"] = None
    atomic_write_state(ws, child, state)
    _invalidate_snapshot(ws)
    audit(ws, asset_type="chain", outcome="chain_detached", verdict="ok",
          source_task=child)
```

注意：**只更新 `child` 自身的 `chain_root`**。子代的 chain_root 不会
跟随父任务的 detach 而变化（M10 不做级联更新；理由见 §11.3）。
读路径在 `walk_ancestors` 时若发现 chain_root 与实际链尾不一致 →
audit `chain_root_stale` 并以实际链尾为准（best-effort 自愈）。

### 3.6 Re-attach 后的语义

允许用户先 detach 再 attach 到不同 parent；此时：

- `chain_root` 重算
- 后续 spawn 的 `{{TASK_CHAIN}}` 内容立刻反映新链（M10 不缓存渲染结果）
- 已经 dispatch 的子 agent 看不到变化（它们读取自身 spawn 时的 prompt
  快照；这是 M8 conversational 模型的既有性质，与 M10 无关）

---

## 4. Interfaces — `_lib/task_chain.py`

### 4.1 模块定位

新文件：`skills/codenook-core/skills/builtin/_lib/task_chain.py`，与
`memory_layer.py` / `extract_audit.py` 同层；**不依赖** memory_layer
（链信息不入 memory），但**复用** `extract_audit.audit()` 写审计。

### 4.2 导出函数（公共 API）

```python
def get_parent(workspace: Path | str, task_id: str) -> Optional[str]:
    """读 state.json 返回 parent_id；任务不存在或 schema 缺字段返回 None。"""

def set_parent(workspace: Path | str, child_id: str, parent_id: str) -> None:
    """原子更新 child.state.json 写 parent_id + chain_root。

    Raises:
        CycleError:           任意自环 / 间接环 / 自指
        TaskNotFoundError:    child 或 parent 的 state.json 不存在
        AlreadyAttachedError: child.parent_id 当前非 null（除非 _force=True 调用）
        ValueError:           parent_id 不符合 _check_task_id 格式
    """

def walk_ancestors(workspace: Path | str, task_id: str, *,
                   max_depth: int | None = None,
                   max_tokens: int | None = None) -> list[str]:
    """child → root 顺序返回链（含 task_id 自身）。

    损坏 / 截断会写 audit 但不抛异常（best-effort 契约）。
    """

def chain_root(workspace: Path | str, task_id: str) -> Optional[str]:
    """返回 chain_root 字段；若缓存为空但 parent_id 非空则即时计算并写回。"""

def detach(workspace: Path | str, task_id: str) -> None:
    """parent_id / chain_root 双置 None；幂等。"""

class CycleError(ValueError):           ...
class TaskNotFoundError(FileNotFoundError): ...
class AlreadyAttachedError(RuntimeError):   ...
```

### 4.3 CLI 入口

```python
# python -m _lib.task_chain attach <child> <parent> [--workspace .] [--force]
# python -m _lib.task_chain detach <child>           [--workspace .]
# python -m _lib.task_chain show   <task>            [--workspace .] [--format=text|json]
```

退出码约定：

| code | 含义 |
|---|---|
| 0 | 成功 |
| 1 | 普通错误（任务不存在、无效 ID） |
| 2 | CycleError |
| 3 | AlreadyAttachedError |
| 64 | CLI 用法错误（来自 argparse） |

`show --format=json` 输出：

```json
{
  "task_id": "T-012",
  "parent_id": "T-007",
  "chain_root": "T-005",
  "ancestors": ["T-012", "T-007", "T-005"],
  "depth": 3,
  "snapshot_hit": true
}
```

### 4.4 错误模式总览

| 场景 | 行为 | audit outcome |
|---|---|---|
| `set_parent` 自环 | `CycleError` | `chain_attach_failed` |
| `set_parent` 间接环 | `CycleError` | `chain_attach_failed` |
| `set_parent` parent 不存在 | `TaskNotFoundError` | `chain_attach_failed` |
| `set_parent` child 已 attached 且无 force | `AlreadyAttachedError` | `chain_attach_failed` |
| `walk_ancestors` 中段任务损坏 | 截断返回 + 不抛 | `chain_walk_truncated` |
| `walk_ancestors` max_depth 命中 | 截断返回 + 不抛 | `chain_walk_truncated` |
| `detach` 已 detach | no-op，不写 audit | — |

---

## 5. Similarity Scorer — `_lib/parent_suggester.py`

### 5.1 算法概览

新文件：`skills/codenook-core/skills/builtin/_lib/parent_suggester.py`。
零外部依赖，纯 Python，与 M9.6 `match_entries_for_task` 思路一致：

1. 用 `_tokenize()` 把 child_brief 与每个候选父任务的 (title + brief)
   分别切成 token 集合。
2. 对每个候选计算 **Jaccard 系数**：`|A ∩ B| / |A ∪ B|`。
3. 排序取 `score >= threshold` 的 top-K，附带 `reason` 字符串
   （列出共有 token 的前 5 个，便于用户判断）。

### 5.2 token 化规则

```python
_PUNCT_RE = re.compile(r"[\s\W_]+", re.UNICODE)

_STOPWORDS = {
    # English
    "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "for",
    "with", "by", "is", "are", "be", "do", "does", "this", "that", "it",
    "as", "at", "from", "into", "than", "then", "so", "if", "we", "i",
    # Chinese (≤ 1-字 高频虚词的常见组合 — 极简清单)
    "的", "了", "和", "在", "是", "我", "你", "他", "她", "它", "我们",
    "你们", "他们", "把", "被", "也", "都", "就", "还", "对",
}

def _tokenize(text: str) -> set[str]:
    if not text:
        return set()
    parts = _PUNCT_RE.split(text.lower())
    return {p for p in parts if p and p not in _STOPWORDS and len(p) >= 2}
```

设计取舍：

- **不引入分词器**（jieba / 中文 NER）：与 M9.6 一致，保证零依赖。
- **lowercase + 长度 ≥ 2**：过滤纯标点、单字母噪声。
- **stopword 列表硬编码**：≤ 50 词，不可配置；用户若有领域词需要排除，
  可在 brief 自身去掉。

### 5.3 候选池

```python
def _list_open_tasks(workspace: Path) -> list[dict]:
    """枚举 .codenook/tasks/<tid>/state.json，过滤 status ∈ {done, cancelled}。

    候选必须满足:
      - state.json 存在且通过 schema 校验
      - status not in {'done', 'cancelled'}
      - task_id != child_id（不让任务挂自己）
    """
```

注意 §11.4 关于「父任务已 done 是否仍可挂」的开放问题；当前默认行为
是**新建链接时排除 done/cancelled**，而**已存在的 done 链接保留**
（chain walk 不因 status 终止）。

### 5.4 候选 brief 抽取

每个候选任务的 brief 由以下来源拼接：

1. `state.json` 的 `title` 与 `summary`（若存在）
2. `draft-config.yaml` 的 `input` 字段（router-agent 起草的任务描述）
3. `router-context.md` 中 **前 3 个** `role: user` 的内容

控制在 ~ 1KB 以内；`_tokenize()` 后通常 ≤ 200 token。

### 5.5 公共 API

```python
class Suggestion(NamedTuple):
    task_id: str
    title:   str
    score:   float           # ∈ [0, 1]
    reason:  str             # e.g. "shared: feature, auth, test"

def suggest_parents(workspace: Path | str,
                    child_brief: str,
                    *,
                    top_k: int = 3,
                    threshold: float = 0.15,
                    exclude_ids: Iterable[str] = ()) -> list[Suggestion]:
    """返回按 score 降序的候选；空列表表示无符合阈值的候选。

    threshold 设为 0.15 的依据:
      - 实测 (M10.0.1 测试用例) 同主题任务通常 ≥ 0.25
      - 不同主题但共享技术栈 token (e.g. 'python', 'test') 通常 ≤ 0.10
      - 0.15 是一个保守的「确实相关而非通用 token 重合」阈值
    """
```

`exclude_ids` 用于排除调用方已知不该建议的任务（如 child_id 本身、
显式黑名单）。

### 5.6 复杂度与缓存

- `O(N · |tokens|)`，N = 开放任务数；典型 workspace N ≤ 50，足够快
  （见 §8 性能预算）。
- **不缓存**结果：每次 spawn 都重新计算（候选池可能有新增）；
  brief tokenize 是纯函数，CPython 下 N=50 时 < 30 ms。

### 5.7 失败语义

- 候选 state.json 损坏 → 跳过该候选 + audit `parent_suggest_skip`
- 整个枚举抛异常 → `suggest_parents` 返回空列表 + audit
  `parent_suggest_failed`；**永不**让 router-agent 因建议失败而无法启动。

---

## 6. Chain Summarizer — `_lib/chain_summarize.py`

### 6.1 模块定位

新文件：`skills/codenook-core/skills/builtin/_lib/chain_summarize.py`。
负责把 `walk_ancestors` 返回的链转化为 router prompt 可注入的
markdown 块。是 M10 唯一调用 LLM 的子系统（其它皆纯文件 I/O）。

### 6.2 输入 / 输出契约

```python
def summarize(workspace: Path | str,
              task_id: str,
              *,
              max_tokens: int = 8192,
              llm_mode: str | None = None) -> str:
    """返回完整的 markdown 块（含 H2 标题），失败时返回空字符串。

    流程:
      1. ancestors = walk_ancestors(ws, task_id)[1:]   # 去掉 self
      2. 若 ancestors 为空 → return ""
      3. 收集每个 ancestor 的元数据 (§6.3)
      4. Pass-1: 逐 ancestor LLM 摘要至 ≤ 1500 token (§6.4)
      5. 估算 Pass-1 总和；若 ≤ max_tokens → 直接渲染 (§6.6)
      6. Pass-2: 整链再压缩，"保留最近 3 个 ancestor 原文，更早的合并
         成 1 段 ≤ 2000 token 的概述" (§6.5)
      7. 渲染并 secret-scan (§9.2)；若 secret 命中 → strip + audit
      8. 返回最终字符串
    """
```

### 6.3 每个 ancestor 收集的数据

| 字段 | 来源 | 用途 |
|---|---|---|
| `task_id` | walk 输入 | section 标题 |
| `title` | `state.json.title` 或 `state.json.task_id` | 标题副文 |
| `phase` | `state.json.phase` | 提供进度上下文 |
| `status` | `state.json.status` | 标识活跃 / 完成 |
| `brief` | `draft-config.yaml.input`（前 1KB） | LLM 摘要的主输入 |
| `decisions` | `decisions.md` 全文（≤ 4KB） | 「关键决策」 |
| `design` | `design.md` 全文（≤ 4KB） | 设计要点 |
| `impl_plan` | `impl-plan.md` 全文（≤ 4KB） | 实现路线 |
| `test` | `test.md` 全文（≤ 4KB） | 测试约定 |
| `artifacts` | `outputs/` 下文件路径 list（最多 20 个） | 产物索引 |

不存在的文件 → 字段缺省，不阻塞。所有读取使用相对路径
`<workspace>/.codenook/tasks/<aid>/<file>`，越界拒绝（防止 `..` 穿透）。

### 6.4 Pass-1：per-ancestor 压缩

LLM 调用：

```python
prompt_p1 = (
    "你是 CodeNook 的链摘要器。下面是任务 {aid} 的完整工作产物。"
    "请输出 ≤ 1500 token 的中文摘要，结构:\n"
    "1. 任务目标 (≤ 100 字)\n"
    "2. 关键决策 (bullet list)\n"
    "3. 已落定的设计点 (bullet list)\n"
    "4. 仍未解决 / 留给子任务 (bullet list)\n\n"
    "—— 原始材料 ——\n{materials}\n"
)
resp = call_llm(prompt_p1, call_name="chain_summarize")
```

`call_name` **统一为 `chain_summarize`**（不细分 pass-1/pass-2，避免
mock 协议爆炸）。两阶段都使用同一 mock 入口，由 prompt 内容区分。

### 6.5 Pass-2：whole-chain 压缩（仅当超额时）

```python
prompt_p2 = (
    "下方是 {N} 段任务摘要，按 child→root 顺序。请重写为新文档:\n"
    "- **完整保留最近 3 段 (newest 3 ancestors) 的原文**\n"
    "- 把更早的所有段合并为 1 段 ≤ 2000 token 的「远祖背景」\n"
    "- 保留每段开头的「## T-XXX」标题以便溯源\n\n"
    "—— 输入 ——\n{joined}\n"
)
```

「保留最近 3 段」的规则取舍：

- **3 段**是经验值：足以承载「父任务 + 祖父任务 + 曾祖任务」的细节；
  更早的祖先与子任务的语义关联通常已经较弱。
- **保留原文 vs 再压**：原文保留有助于子任务直接引用决策，再压会丢
  细节；优先保原文，靠远祖压缩腾出预算。

### 6.6 渲染格式

```markdown
## TASK_CHAIN (M10)

This task descends from {N} ancestor(s). Newest first.

### T-007 — feature/auth (phase: implement, status: done)

**目标**：实现基于 JWT 的登录 / 登出 / 刷新。

**关键决策**：
- 使用 bcrypt cost=12
- refresh token 7d、access token 15min
- ...

**产物**：
- `outputs/auth_router.py`
- `outputs/test_auth.py`
- `decisions.md`

### T-005 — bootstrap (phase: design, status: done)

...
```

### 6.7 Mock 协议

完全沿用 `_lib/llm_call.py` 的 mock 解析顺序（spec memory §6 的
M9.0.1 协议）：

```
1. $CN_LLM_MOCK_DIR/chain_summarize.json | .txt           （文件）
2. $CN_LLM_MOCK_CHAIN_SUMMARIZE                            （环境变量）
3. $CN_LLM_MOCK_RESPONSE                                   （环境变量；通用回退）
4. $CN_LLM_MOCK_FILE                                       （文件路径）
5. fallback: "[mock-llm:chain_summarize] {prompt[:80]}"    （内置）
```

这给测试三档灵活度：

- bats 用 `CN_LLM_MOCK_DIR=$BATS_TMPDIR/mock` + 预置 fixture 文件
- 单元测试用 `CN_LLM_MOCK_CHAIN_SUMMARIZE` 环境变量
- 端到端冒烟用 `CN_LLM_MOCK_RESPONSE` 模拟所有 LLM 一致响应

### 6.8 失败处理

任意环节抛异常（LLM 超时 / pass-1 返回空 / pass-2 文件 I/O 失败 /
secret-scan 拦截）→：

1. `summarize()` 返回空字符串 `""`
2. 写 audit `chain_summarize_failed`，`reason` 字段记录异常类型与
   ancestor 数
3. router-agent 把空字符串注入 `{{TASK_CHAIN}}` slot（slot 仍存在，
   只是为空）
4. **不抛异常给上游**，spawn 流程继续

退出策略与 M9 抽取器（§5.4 of memory spec）一致：永不阻塞主流程。

---

## 7. Router Integration

### 7.1 prompt.md 的 slot 增量

在 `skills/codenook-core/skills/builtin/router-agent/prompt.md` 中，
**`{{USER_TURN}}` 之上、`{{MEMORY_INDEX}}` 之上**新增一段：

```markdown
{{TASK_CHAIN}}
```

最终顺序（自顶向下）变为：

```
... (header / WORKSPACE / PLUGINS_SUMMARY / ROLES / OVERLAY) ...

{{TASK_CHAIN}}        ← M10 NEW

{{MEMORY_INDEX}}

---

## Current router-context (frontmatter) ...
## Conversation so far ...
## Latest user turn ...
{{USER_TURN}}
```

设计依据：

- 链上下文是**当前任务的因果先验**，应在 router 「读」其它索引前先
  到位（让 LLM 用链信息为 memory_index 的取舍提供线索）。
- 放在 `{{USER_TURN}}` 上方但不与 user turn 紧贴，留出 memory_index
  作为「近距修饰」(M9 既有约束)。

### 7.2 render_prompt.py 的代码增量

在 `_render_memory_index` 调用之前增加：

```python
import task_chain as tc                  # noqa: E402  (M10)
import chain_summarize as cs             # noqa: E402  (M10)

def _render_task_chain(workspace: Path, task_id: str, state: dict) -> str:
    if not state or state.get("parent_id") is None:
        return ""
    try:
        return cs.summarize(workspace, task_id)
    except Exception:
        # Defensive: cs.summarize already swallows internal failures,
        # this is double-belt for unexpected programming errors.
        return ""
```

并在 `subs` 字典里：

```python
subs = {
    ...,
    "{{TASK_CHAIN}}":  _render_task_chain(workspace, task_id, state),
    "{{MEMORY_INDEX}}": _render_memory_index(memory_matches),
    ...
}
```

`state` 来源：复用 `render_prompt.py` 已经为 handoff 路径加载的
`state.json`（M8 的 `freeze_to_state_json` 路径）；prepare 路径若
state.json 尚不存在（首次 spawn），`state = {}` → `parent_id` 缺失 →
slot 为空。

### 7.3 token 预算

| slot | M9 预算 | M10 调整 |
|---|---|---|
| `{{MEMORY_INDEX}}` | ≤ 4K（spec memory §11.2） | **不变** |
| `{{TASK_CHAIN}}` | — | **新增 ≤ 8K**（与 chain summarizer max_tokens 一致） |
| router prompt 总额 | ≤ 16K | **抬升至 ≤ 20K**（+4K 净增；非 +8K，因 chain 平均显著短于上限） |

总额从 16K 抬至 20K 的依据：典型 chain 摘要在 1.5K–4K token，最坏 8K
受 §6.4/6.5 强约束；其余 16K 给 plugins/roles/memory/conversation
预留与 M9 一致。

### 7.4 与 MEMORY_INDEX 的语义边界

| 维度 | MEMORY_INDEX | TASK_CHAIN |
|---|---|---|
| 作用域 | 项目级常驻知识 | 当前任务谱系 |
| 触发条件 | 总是渲染（即使为空也显式说明） | 仅当 `parent_id != null` |
| 写入路径 | `.codenook/memory/` | 不写（即用即弃；只写 audit） |
| 来源生成 | LLM 抽取器（M9.3–M9.5） | LLM chain summarizer（M10.4） |
| 失败 fallback | 空 marker block | 空字符串（不渲染 marker） |

router-agent 应将 `TASK_CHAIN` 视为「先验事实」，把 `MEMORY_INDEX`
视为「可选参考」；prompt.md 中无需新增解释——LLM 看到结构化标题
（`## TASK_CHAIN (M10)`）即可正确推断。

### 7.5 spawn.sh 无变更

`spawn.sh` 仅是 `render_prompt.py` 的薄封装；M10 不修改 shell 层。
`render_prompt.py --confirm` 路径同样需要在 `freeze_to_state_json`
之后调用 `task_chain.set_parent`（如果用户在对话中确认了候选父任务）。
该集成在 M10.3 实施。

---

## 8. Budgets & Performance

### 8.1 walk_ancestors 性能预算

| 链深度 | 目标 P95 walk 耗时 |
|---|---|
| ≤ 5 | < 30 ms |
| ≤ 10 | < 100 ms |
| ≤ 50 | < 500 ms（仅安全网，正常使用不会到达） |

实现策略：

1. **chain-snapshot 缓存**：`<workspace>/.codenook/tasks/.chain-snapshot.json`
   存储所有任务的 `(task_id, parent_id, chain_root, mtime)`；walk 时
   不再逐个打开 state.json。
2. **失效协议**：snapshot 头部记 `generation: int`；任一 `set_parent`
   / `detach` → `generation += 1`，walk 在使用前比对所有相关任务
   `state.json` 的 `mtime` 与 snapshot 中记录是否一致；不一致 → 重建
   该任务的条目。
3. **完整重建**：snapshot 文件不存在 / generation 字段缺失 → 全量
   扫描 `.codenook/tasks/*/state.json` 重建（O(N)，N=任务总数）。
4. **gitignore**：snapshot 加入 `.codenook/.gitignore`（与 M9.1 的
   `.index-snapshot.json` 同处）。

### 8.2 Snapshot 文件格式

```json
{
  "schema_version": 1,
  "generation": 17,
  "built_at": "2026-04-21T08:00:00Z",
  "entries": {
    "T-007": {
      "parent_id": "T-005",
      "chain_root": "T-005",
      "state_mtime": "2026-04-20T14:33:21Z"
    },
    "T-012": { ... }
  }
}
```

### 8.3 chain_summarize wall-clock 预算

| 链深度 | 目标 P95 总耗时（含 LLM） |
|---|---|
| ≤ 3 | ≤ 8 s |
| ≤ 10 | ≤ 30 s |
| > 10 | best-effort，不设上限；超 60 s → 强制 timeout 走 fail 路径 |

LLM 端是主要耗时项；M10 不并行调用 pass-1（顺序执行更易调试）。
若用户路径压力大，M11 可考虑并行（开放问题 §11.5）。

### 8.4 内存 / 磁盘开销

- snapshot 文件：每任务约 200 byte，N=1000 时 < 200 KB → 忽略。
- 摘要审计行：每条 audit 在 `.codenook/memory/history/extraction-log.jsonl`
  中追加一行 < 500 byte；这条 jsonl 已由 M9.1 logrotate 策略管理
  （memory spec §10.5），M10 不另立文件。
- chain 摘要文本本身**不落盘**，只在 prompt 中存活；router-context
  归档时（M9.6 8 轮归档器）会包含历史 prompt 的全文，因此可追溯。

### 8.5 退化路径性能

snapshot 失效或损坏时的退化路径（重新 O(N) 扫描）必须仍满足
N=200 任务下 < 1s 的目标，否则触发 audit `chain_snapshot_slow_rebuild`
（仅观测，不影响功能）。

---

## 9. Security & Audit

### 9.1 audit outcomes（与 M9 共享 logger）

新增 6 个 outcome，全部经 `extract_audit.audit()` 写入
`.codenook/memory/history/extraction-log.jsonl`，asset_type 固定为
`"chain"`：

| outcome | 触发点 | 关键 reason 字段 |
|---|---|---|
| `chain_attached` | `set_parent` 成功 | `parent={pid},root={rid}` |
| `chain_attach_failed` | `set_parent` 抛异常 | `error=cycle\|not_found\|already_attached\|invalid_id` |
| `chain_detached` | `detach` 实际写盘 | (空) |
| `chain_summarized` | `summarize` 成功返回非空 | `depth={N},tokens≈{T},pass2={true\|false}` |
| `chain_summarize_failed` | `summarize` 任意失败 | `error={exception_class}:{msg[:100]}` |
| `chain_walk_truncated` | walk 因损坏 / max_depth 截断 | `at={tid},reason=corrupt\|max_depth` |

补充观测性 outcome（`outcome=diagnostic, verdict=noop` side-record；
spec memory §10.5 的 extra 协议）：

| extra.kind | 用途 |
|---|---|
| `parent_suggest_skip` | 候选 state.json 损坏被跳过 |
| `parent_suggest_failed` | 整次建议失败 |
| `chain_root_stale` | walk 发现缓存与实际不一致 |
| `chain_snapshot_slow_rebuild` | 退化路径耗时超阈 |

### 9.2 secret 扫描

链摘要可能在源 ancestor 文件中夹带配置 / 密钥（`decisions.md` 经常
记录 token 长度、连接串模板等）。在 `chain_summarize.summarize()`
返回前，**强制**调用 `_lib/secret_scan.scan_secrets(text)`：

```python
hit, sample = secret_scan.scan_secrets(rendered)
if hit:
    rendered = secret_scan.redact(rendered)
    audit(ws, asset_type="chain",
          outcome="chain_summarize_failed",
          verdict="redacted",
          source_task=task_id,
          reason=f"secret_hit:{sample[:32]}")
```

设计要点：

- **redact 而非 fail-close**：链摘要被 redact 后仍有价值；不像 M9.3
  抽取器要拒绝写盘，因为这里是 prompt-only。
- audit outcome 复用 `chain_summarize_failed` 是有意的：把 redact 视为
  「部分失败」语义统一，verdict=`redacted` 区分原因。
- secret 模式集复用 M9.3 的纯正则（sk- / ghp_ / AKIA / BEGIN PRIVATE KEY
  等），M10 不新增模式。

### 9.3 plugin_readonly 边界

`chain_summarize` 仅写以下两类文件：

1. `.codenook/memory/history/extraction-log.jsonl`（经 `extract_audit.audit`）
2. `.codenook/tasks/<tid>/state.json`（经 `task_chain.set_parent` / `detach`）
3. `.codenook/tasks/.chain-snapshot.json`（经 `_invalidate_snapshot` 与重建）

**不**写：

- `.codenook/plugins/`（plugin_readonly_check 由 M9.7 守护）
- `.codenook/memory/{knowledge,skills}/` 或 `config.yaml`（chain 不入 memory）
- 任务工作目录之外的项目文件

### 9.4 路径穿透防御

`chain_summarize` 在读取 `decisions.md` / `design.md` 等文件时，
必须用 `(workspace_root / ".codenook" / "tasks" / aid / fname).resolve()`
然后断言其位于 `(workspace_root / ".codenook" / "tasks" / aid).resolve()`
之内（防止 `aid="../../../etc"` 之类构造）。等价于复用
`_lib/atomic.assert_within(parent, child)`（M5 既有 helper）。

### 9.5 多任务并发

`set_parent` / `detach` 写 `state.json` 时复用 `_lib/atomic.atomic_write_json`，
依赖 OS rename 原子性；snapshot 重建用 `_lib/task_lock` 取 fcntl 锁（与
router-agent 已用的同一锁文件 `<workspace>/.codenook/tasks/.lock`），避免
两个 spawn 并发重建产生交叉写。

---

## 10. Backward Compatibility

### 10.1 与 M0–M9 任务的共存

- M9 及之前创建的任务：`state.json` 没有 `parent_id` / `chain_root`
  字段。read 路径 (`get_parent`) 把缺字段视同 `None`，行为等价于
  「独立任务」。**不需要任何一次性转换脚本**。
- M9 抽取器 / router-agent 行为完全不变：`{{TASK_CHAIN}}` 在
  `parent_id is None` 时为空字符串，prompt 末态与 M9 一致（多一行
  空白可忽略）。
- `task-state.schema.json` 仅追加 `additionalProperties` 默认 `false`
  之外的两个新字段；`required` 列表不变 → 旧 state.json 仍通过
  schema 验证。

### 10.2 不引入历史包袱语汇

按 plan.md 「Greenfield rule」，本文与 M10 任何代码 / 测试 / 文档
**禁止出现** plan.md 列出的全部历史 / 转换 token。前向语义统一用
「叠加」「共存」「增量」「可选字段」等词表达。

### 10.3 上游 / 下游影响

| 子系统 | M10 影响 |
|---|---|
| init skill | 无（不创建新目录，snapshot 按需懒生成） |
| memory_layer | 无（chain 不入 memory） |
| memory_index | 无 |
| extractor-batch / 三类抽取器 | 无 |
| router-agent prompt.md | 新增一行 `{{TASK_CHAIN}}` slot |
| render_prompt.py | 新增 `_render_task_chain` + 2 个 import |
| spawn.sh | 无 |
| orchestrator-tick | 无（不读 parent_id；调度仍用 depends_on） |
| plugin_readonly_check | 无（chain 不写 plugins/） |
| sec-audit / dispatch-audit | 无 |

### 10.4 .gitignore 策略

`.codenook/tasks/.chain-snapshot.json` 加入 `.codenook/.gitignore`：

```
# M9
memory/.index-snapshot.json
# M10
tasks/.chain-snapshot.json
```

snapshot 是纯 derived data，提交后会因 generation 漂移产生大量
噪声 diff。

---

## 11. Open Questions

留给 M10.0.1 / M10.x 实施期 sub-agent 决策；当前默认值在括号中。

### 11.1 Sibling 上下文是否进入 router prompt？

兄弟任务（同 `parent_id` 的姐妹任务）是否也聚合？
**默认：否**。理由：兄弟任务通常是并行展开的「同级试探」，引入会
急剧扩大 token 预算且可能给 router 误导信号。可在 M11 评估
「sibling-aware 模式」。

### 11.2 用户在对话中改变意图，是否触发 re-suggest？

router-agent 是否在每次 user turn 都重新跑 `parent_suggester`？
**默认：是，但只在用户尚未确认 `parent_id` 时**。一旦
`state.json.parent_id` 写入，suggester 不再插话，避免反复打扰。
如何检测 「用户改变意图」 → 「想要换 parent」？M10 的简化做法：
依赖用户显式 `task-chain detach`；不在 router-agent 内做意图分析。

### 11.3 父任务被 archived/closed，子任务还能继续 walk 吗？

**默认：是**。`walk_ancestors` 不读取 `status` 字段，链结构与生命
周期解耦。`status=cancelled` 的祖先仍提供历史背景；UI 层（M11）
可在显示时标注「已取消」以减少 router 的困惑。

### 11.4 `parent_suggester` 是否应包含 done 任务？

**默认：否**。建议候选只覆盖 `status not in {done, cancelled}` 的
开放任务。理由：用户多数情况下想把新任务接到「正在做的事」上；
若确实想挂到已完成任务，使用 `task-chain attach` CLI 显式指定。

### 11.5 Pass-1 LLM 是否并行？

**默认：否**。顺序调用更易 mock / 调试 / 写 audit；并行化收益
（性能）vs 复杂度（错误恢复 / 审计顺序）权衡留待 M11。

### 11.6 是否限制 max chain depth？

理论可任意深；§3.4 仅在数据损坏导致无限循环时用 `max_depth=100`
保险丝。**正常路径不限深度**；token 预算靠 §6.5 的两阶段压缩处理。

### 11.7 「父任务被删除」如何处理？

CodeNook 当前没有删除任务的官方 CLI（任务只能 cancel）。若用户手动
`rm -rf .codenook/tasks/T-005`：

- `walk_ancestors` 在该 ancestor 处截断 + `chain_walk_truncated` audit
- 子任务 `chain_root` 缓存可能 stale → §3.5 的自愈逻辑接住

不需要专门的「孤儿子任务修复」流程。

---

## 12. Acceptance Criteria Mapping

下表把本文约束映射到 M10.0.1 测试用例文档（`docs/v6/m10-test-cases.md`）
将引用的 AC 编号；**测试用例文档以本表为合同**。

| AC ID | 来源章节 | 验收要点 | 计划测试文件 |
|---|---|---|---|
| AC-CHAIN-MOD-1 | §2.3 | `state.json` 增加 `parent_id` 后通过 schema 校验 | `m10-schema.bats` |
| AC-CHAIN-MOD-2 | §2.5 | `set_parent` 自环抛 `CycleError` | `m10-task-chain.bats` |
| AC-CHAIN-MOD-3 | §2.5 | `set_parent` 间接环抛 `CycleError` | `m10-task-chain.bats` |
| AC-CHAIN-MOD-4 | §2.3 | `parent_id != null` ⇒ `chain_root` 等于沿父链终点 | `m10-task-chain.bats` |
| AC-CHAIN-LINK-1 | §3.3 | CLI `attach` 写入 parent_id + chain_root | `m10-task-chain-cli.bats` |
| AC-CHAIN-LINK-2 | §3.3 | CLI `detach` 幂等 | `m10-task-chain-cli.bats` |
| AC-CHAIN-LINK-3 | §3.3 | CLI `show` 输出 child→root 顺序 | `m10-task-chain-cli.bats` |
| AC-CHAIN-LINK-4 | §3.3 | `attach` 在已 attached 任务上默认拒绝 | `m10-task-chain-cli.bats` |
| AC-CHAIN-SUG-1 | §5.5 | `suggest_parents` 返回按 score 降序的 ≤ top_k | `m10-parent-suggester.bats` |
| AC-CHAIN-SUG-2 | §5.5 | score < 0.15 不出现在结果里 | `m10-parent-suggester.bats` |
| AC-CHAIN-SUG-3 | §5.3 | done / cancelled 任务不进入候选池 | `m10-parent-suggester.bats` |
| AC-CHAIN-SUG-4 | §5.7 | suggester 异常 → 返回空列表 + audit | `m10-parent-suggester.bats` |
| AC-CHAIN-CTX-1 | §7.1 | `prompt.md` 含 `{{TASK_CHAIN}}` slot | `m10-prompt-slots.bats` |
| AC-CHAIN-CTX-2 | §7.2 | `parent_id is None` ⇒ slot 为空字符串 | `m10-render-prompt.bats` |
| AC-CHAIN-CTX-3 | §7.2 | `parent_id != None` ⇒ slot 调用 `chain_summarize` | `m10-render-prompt.bats` |
| AC-CHAIN-CTX-4 | §6.6 | 渲染包含每个 ancestor 的 H3 + artifacts 列表 | `m10-chain-summarize.bats` |
| AC-CHAIN-BUD-1 | §6.4 | pass-1 输出每段 ≤ 1500 token (mock 验证) | `m10-chain-summarize.bats` |
| AC-CHAIN-BUD-2 | §6.5 | pass-1 总和 > 8K ⇒ 触发 pass-2 | `m10-chain-summarize.bats` |
| AC-CHAIN-BUD-3 | §6.5 | pass-2 完整保留最近 3 ancestor | `m10-chain-summarize.bats` |
| AC-CHAIN-NF-1 | §6.8 | LLM 抛错 ⇒ `summarize` 返回空字符串 + audit | `m10-chain-summarize.bats` |
| AC-CHAIN-NF-2 | §3.4 | walk 中段损坏 ⇒ 截断返回，不抛 | `m10-task-chain.bats` |
| AC-CHAIN-NF-3 | §9.2 | secret 命中 ⇒ redact + audit | `m10-chain-secret.bats` |
| AC-CHAIN-PERF-1 | §8.1 | depth ≤ 10 walk < 100 ms (snapshot 命中) | `m10-chain-perf.bats` |
| AC-CHAIN-PERF-2 | §8.5 | snapshot 损坏 ⇒ N=200 重建 < 1 s | `m10-chain-perf.bats` |
| AC-CHAIN-AUD-1 | §9.1 | 6 个核心 outcome 全部能在 jsonl 中观察到 | `m10-chain-audit.bats` |
| AC-CHAIN-AUD-2 | §9.1 | audit 行复用 `extract_audit.audit()` 8-key schema | `m10-chain-audit.bats` |
| AC-CHAIN-RO-1 | §9.3 | mock 强行写 `plugins/` 路径 ⇒ M9.7 guard 抛错 | `m10-chain-readonly.bats` |
| AC-CHAIN-COMPAT-1 | §10.1 | 缺 `parent_id` 字段的 state.json 仍通过校验 | `m10-schema.bats` |
| AC-CHAIN-COMPAT-2 | §10.3 | 现有 M9 bats 套件全部不受影响 (regression) | `m9-*.bats` re-run |

E2E 验收（M10.7）：

| AC ID | 验收要点 | 测试文件 |
|---|---|---|
| AC-CHAIN-E2E-1 | 创建任务 → suggester top-3 → 用户选 parent → state.json 落盘 | `tests/e2e/m10-e2e.bats` |
| AC-CHAIN-E2E-2 | 子任务 spawn 时 prompt 含正确祖先摘要 | `tests/e2e/m10-e2e.bats` |
| AC-CHAIN-E2E-3 | depth=8 链 → pass-2 触发 → prompt ≤ 20K | `tests/e2e/m10-e2e.bats` |
| AC-CHAIN-E2E-4 | LLM 失败 → spawn 不退非零，prompt 含其它 slot | `tests/e2e/m10-e2e.bats` |

---

## 附录 A · 与 memory spec 的对照速查

| 概念 | M9 / memory spec | M10 / chain spec |
|---|---|---|
| 写入位置 | `.codenook/memory/...` | `.codenook/tasks/<tid>/state.json`（新增 2 字段）+ `.chain-snapshot.json` |
| 抽取触发 | `after_phase` hook + 80% 水位 | spawn 时同步触发（无 hook） |
| LLM call_name | `knowledge_extract`, `skill_extract`, `config_extract` | `chain_summarize`（单一） |
| Mock 协议 | `_lib/llm_call.py` §6 | 与 M9 完全一致；只换 `call_name` |
| 失败语义 | best-effort，audit 不阻塞 | best-effort，audit 不阻塞 |
| Index 缓存 | `memory/.index-snapshot.json` | `tasks/.chain-snapshot.json` |
| Audit logger | `extract_audit.audit()` 8-key | 同上（asset_type=`"chain"`） |
| Router slot | `{{MEMORY_INDEX}}` | `{{TASK_CHAIN}}` |
| Token 预算 | ≤ 4K | ≤ 8K |

---

## 附录 B · 默认值速览（自动模式直接采纳）

供 M10.x sub-agent 在缺乏人工确认时直接采用：

1. `parent_suggester` 阈值：`0.15`
2. `parent_suggester` top_k：`3`
3. `chain_summarize` per-ancestor token：`1500`
4. `chain_summarize` 总预算：`8192`
5. `chain_summarize` pass-2 「最近 N 段保原文」：`3`
6. `chain_summarize` LLM 单次 timeout：`30s`（`call_llm` 默认）
7. `walk_ancestors` 安全 max_depth：`100`
8. snapshot 文件名：`tasks/.chain-snapshot.json`
9. snapshot generation 起始：`1`
10. CLI 退出码：`0/1/2/3/64`（见 §4.3）
11. `attach` 在已 attached 任务上的默认行为：拒绝（需 `--force`）
12. include sibling in router prompt：`false`
13. include done tasks in suggestions：`false`
14. include done ancestors in walk：`true`

---

## 附录 C · 章节交叉索引

- §1 ←→ G-CHAIN-1..5
- §2 ←→ AC-CHAIN-MOD-*, AC-CHAIN-COMPAT-1
- §3 ←→ AC-CHAIN-LINK-*, AC-CHAIN-NF-2
- §4 ←→ AC-CHAIN-LINK-*, AC-CHAIN-MOD-2/3
- §5 ←→ AC-CHAIN-SUG-*
- §6 ←→ AC-CHAIN-CTX-3/4, AC-CHAIN-BUD-*, AC-CHAIN-NF-1
- §7 ←→ AC-CHAIN-CTX-1/2/3
- §8 ←→ AC-CHAIN-PERF-*
- §9 ←→ AC-CHAIN-NF-3, AC-CHAIN-AUD-*, AC-CHAIN-RO-1
- §10 ←→ AC-CHAIN-COMPAT-*
- §11 ←→ 开放问题，无直接 AC

— END OF M10.0 SPEC —

# CodeNook v0.10 功能验收测试规格 (FAT)

> 版本：v0.10.0-m10.0 / FAT-Phase2
> 编写日期：2026-04
> 关联文档：`docs/v6/requirements-v0.10.md`（SRS，Phase 1）
> 文档维护者：CodeNook Core Team

---

## 1. 文档概述

### 1.1 目的

本文档把 SRS（`requirements-v0.10.md`）每一条 FR / NFR 翻译为**可执行的验收测试用例（Acceptance Test, AT）**。
作为 v0.10 验收阶段的执行清单：

- Phase 2（本文档）：定义全部 AT；
- Phase 3：执行 AT、回填实际状态；
- Phase 4：依据本文档 + Phase 3 结果生成 HTML 验收报告。

### 1.2 范围

- **覆盖**：SRS §3 全部 FR（INIT/INSTALL/TASK/TICK/ROUTER/CHAIN/MEM/EXTRACT/DIST/SKILL/PLUGIN/ROLE/CONFIG/LLM/SEC/QUEUE/SESS/HITL/CTX）+ §4 全部 NFR + §A 不一致与 spec 缺漏的处理决策；
- **不覆盖**：未实现项（SRS §7「已知限制」）、第三方业务插件、HTML/podcast/slides 演示物。

### 1.3 验收方法

每条 AT 有且仅有一种主要验收方法（次要方法可叠加）：

| 方法标记 | 含义 | 触发执行命令 |
|---------|------|-------------|
| `[已有 bats]` | 当前 `skills/codenook-core/tests/*.bats` 已覆盖；Phase 3 仅执行 `bats` 复核 | `bats -F pretty skills/codenook-core/tests/<file>.bats -f "<grep>"` |
| `[需新增 bats]` | SRS 行为存在但未编写自动化用例；Phase 3 须补 bats | 详见 §8.2 |
| `[手动]` | 涉及 fcntl 死锁恢复、kill -9 等需 reviewer 介入的步骤 | 手册化清单 |
| `[文档检查]` | 仅校验 SRS / spec / CLI help 的文字一致性 | `grep` / 目视 |
| `[smoke E2E]` | 串联 ≥3 个 skill 的端到端冒烟 | §5 节给出 fixture |
| `[linter]` | 调用 `claude_md_linter` / `plugin_readonly` 等内置静态扫 | 已封装的 CLI |

### 1.4 通过判据（VERDICT）

每条 AT 在 Phase 3 必须落出三态：

| VERDICT | 含义 |
|---------|------|
| **PASS** | 全部「预期结果」断言为真；exit code 与输出匹配 |
| **PARTIAL** | 主断言通过但存在 §A 标注的已知偏差（按 code 验为 PASS、按 spec 验为 FAIL，二者不一致） |
| **FAIL** | 任一关键断言失败；需写 issue 与修复 PR |

PARTIAL 出现时必须在 Phase 3 汇总表（§7）的「备注」列引用 §6 的不一致编号。

### 1.5 优先级

| 级别 | 标准 | Phase 3 顺序 |
|------|------|-------------|
| **P0** | 路径必经 / 数据完整性 / 安全 redact / 锁与原子写 | 第一批，必须全 PASS 否则阻断验收 |
| **P1** | 主流程业务功能（router 路由、tick 推进、抽取、链路、配置） | 第二批，PARTIAL 可放行 |
| **P2** | 边界 / 优化 / 兼容性 / 性能预算 | 第三批，可延后到 v0.11 |

---

## 2. 验收环境

### 2.1 软件依赖

| 工具 | 最低版本 | 用途 |
|------|---------|------|
| `bash` | 3.2+ | 全部 bats / shell skill |
| `bats-core` | 1.10+ | 自动化测试 runner |
| `python3` | 3.9+ | `_lib/*.py`（fcntl 必需 → 仅 POSIX） |
| `jq` | 1.6+ | JSON 断言、payload 解析 |
| `git` | 2.30+ | clean checkout / diff |
| `coreutils` | – | `stat`, `du`, `wc`, `sha256sum`（macOS 用 `gstat` / `gsha256sum`） |
| `python3 -m pip install pyyaml` | – | YAML 解析（仅 distiller / config） |

可选：`gnu-time`（perf AT 计时）、`shellcheck`（lint 闸门复核）。

### 2.2 仓库 clean checkout 步骤

```bash
git clone git@github.com:cintia09/CodeNook.git CodeNook-fat
cd CodeNook-fat
git checkout v0.10.0   # 或对应 release tag
git status             # 必须 clean
git rev-parse HEAD     # 记录到 §7 汇总表
mkdir -p .scratch      # 工作目录
```

### 2.3 工作目录约定

- `.scratch/` —— 所有 AT 临时 workspace、mock 文件、fixture 复制品；**不进 git**；
- `.scratch/ws-<at-id>/` —— 单条 AT 用的隔离 workspace；
- `.scratch/audit/` —— Phase 3 汇总输出；
- `CN_LLM_MOCK_DIR=$PWD/.scratch/mock` —— LLM mock 文件目录（沿用 M9/M10 协议）；
- `CODENOOK_WORKSPACE=$PWD/.scratch/ws-<at-id>` —— 各 AT 入口约定。

清理：`rm -rf .scratch && mkdir -p .scratch`。

### 2.4 全局环境变量

| 变量 | 默认 | 用途 |
|------|------|------|
| `CN_LLM_MOCK_DIR` | `.scratch/mock` | 各 LLM call 注入 mock 响应 |
| `CN_LLM_MOCK_RESPONSE` | – | 覆盖全部 mock |
| `CODENOOK_WORKSPACE` | 当前 ws | 等价于 `--workspace` |
| `CODENOOK_REQUIRE_SIG` | `0` | G05 强制 signature |
| `CODENOOK_LOCK_TIMEOUT_S` | `30` | router.lock 超时（仅测试加速） |


---

## 3. 验收用例

> 编号格式：`AT-<SUBSYS>-NN`，与 SRS `FR-<SUBSYS>-NN` 一一映射；同一 FR 多用例时升序追加。
> 每条 AT 末尾的「现有 bats」列直接 grep `skills/codenook-core/tests/` 而得；缺失即标 `[需新增 bats]`。

### 3.1 INIT — 工作区与仓库初始化

#### AT-INIT-1.1：init 生成完整骨架（幂等）
- **覆盖需求**：FR-INIT-1
- **前置条件**：clean `.scratch/ws-init-1/`，无 `.codenook/`
- **执行步骤**：
  1. `mkdir -p .scratch/ws-init-1 && cd .scratch/ws-init-1`
  2. `bash ../../skills/codenook-core/skills/builtin/init/init.sh .`
  3. `find .codenook/memory -maxdepth 2 -type d | sort`
  4. `cat .codenook/memory/config.yaml`
  5. 重复执行步骤 2，`diff -r .codenook old.codenook`（先备份）
- **预期结果**：
  - 退出码 0
  - 存在 `.codenook/memory/{knowledge,skills,history}/` 与 `.codenook/memory/config.yaml`
  - `config.yaml` 含 `version: 1`
  - `.gitignore` 包含 `.codenook/memory/.index-snapshot.json` 与 `.codenook/.chain-snapshot.json`
  - 重复执行后无 diff（幂等）
- **验收方法**：`[需新增 bats]`（当前 m1-init-help.bats 仅覆盖 --help / --version，未覆盖完整骨架）
- **优先级**：P0

#### AT-INIT-1.2：init --help / --version
- **覆盖需求**：FR-INIT-1（CLI 边界）
- **前置条件**：仓库 clean
- **执行步骤**：
  1. `bash skills/codenook-core/skills/builtin/init/init.sh --help`
  2. `bash skills/codenook-core/skills/builtin/init/init.sh --version`
- **预期结果**：
  - 步骤 1 exit 0；输出含 `CodeNook v6` + 子命令列表（`--install-plugin --scaffold-plugin --pack-plugin --uninstall-plugin --upgrade-core --refresh-models --version`）
  - 步骤 2 exit 0；输出含 `cat skills/codenook-core/VERSION` 的内容
- **验收方法**：`[已有 bats]` `tests/m1-init-help.bats`（"init.sh --help exits 0..."、"--help lists all M1 subcommands"、"--version exits 0..."）
- **优先级**：P1

#### AT-INIT-2.1：仓库级 install.sh 复制 core
- **覆盖需求**：FR-INIT-2
- **前置条件**：`.scratch/ws-install-2/` clean
- **执行步骤**：
  1. `./install.sh .scratch/ws-install-2`
  2. `ls .scratch/ws-install-2/.codenook/core/skills/builtin | head`
- **预期结果**：
  - 退出码 0
  - 目标目录含 `.codenook/core/skills/builtin/{init,router,orchestrator-tick,...}`
  - `_lib/` 目录被同步
- **验收方法**：`[需新增 bats]`（仓库根脚本，无现成 bats）
- **优先级**：P1

---

### 3.2 INSTALL — 12 闸门安装管线

#### AT-INSTALL-1.1：12 gate 全通过 → atomic commit
- **覆盖需求**：FR-INSTALL-1
- **前置条件**：备好合规 plugin 源 `tests/fixtures/plugins/<good>/`
- **执行步骤**：
  1. `bash skills/codenook-core/skills/builtin/install-orchestrator/orchestrator.sh --src tests/fixtures/plugins/good --workspace .scratch/ws-inst --json > out.json`
  2. `jq '.gates[] | {gate, ok}' out.json`
  3. `ls .scratch/ws-inst/.codenook/plugins/`
- **预期结果**：
  - 退出码 0
  - `gates` 数组按 G01→G12 顺序，全部 `ok: true`
  - `.codenook/plugins/<id>/` 出现，包含原插件全部文件
  - `state.json.installed_plugins[]` 追加该 id
- **验收方法**：`[已有 bats]` `tests/m2-install-orchestrator.bats`
- **优先级**：P0

#### AT-INSTALL-1.2：任一 gate 失败整体 exit 1
- **覆盖需求**：FR-INSTALL-1
- **前置条件**：构造一个 `plugin.yaml` 缺 `id` 的 fixture
- **执行步骤**：
  1. `bash .../install-orchestrator/orchestrator.sh --src <bad-fixture> --workspace .scratch/ws-inst-bad`
- **预期结果**：
  - 退出码 1
  - `.codenook/plugins/<bad-id>/` **不存在**（commit 未发生）
  - stderr / json 含失败 gate id
- **验收方法**：`[已有 bats]` `tests/m2-install-orchestrator.bats`
- **优先级**：P0

#### AT-INSTALL-1.3：已存在同 id 不传 --upgrade → exit 3
- **覆盖需求**：FR-INSTALL-1
- **执行步骤**：
  1. 先成功安装 plugin foo
  2. 再次安装同 id 不带 `--upgrade` → exit 3
  3. 加 `--upgrade` 且 version 严格大于 → exit 0
- **预期结果**：exit 3 / 0；stderr 提示 "already installed"
- **验收方法**：`[已有 bats]` `tests/m2-install-orchestrator.bats` + `m2-plugin-id-validate.bats`
- **优先级**：P1

#### AT-INSTALL-1.4：--dry-run 走完所有 gate 但跳过 commit
- **覆盖需求**：FR-INSTALL-1
- **执行步骤**：
  1. `... orchestrator.sh --src good --workspace ws --dry-run --json`
  2. `ls ws/.codenook/plugins/`
- **预期结果**：exit 0；全 12 gate ok=true；`.codenook/plugins/` 不出现该插件
- **验收方法**：`[需新增 bats]`（现有 bats 未测 --dry-run 路径）
- **优先级**：P1

#### AT-INSTALL-G01：plugin-format
- **覆盖需求**：FR-PLUGIN-G01
- **执行步骤**：
  1. `bash .../plugin-format/format-check.sh --src <fixture-with-bad-yaml> --json`
- **预期结果**：缺 plugin.yaml → exit 1；越界 symlink → exit 1
- **验收方法**：`[已有 bats]` `tests/m2-plugin-format.bats`
- **优先级**：P0

#### AT-INSTALL-G02：plugin-schema
- **覆盖需求**：FR-PLUGIN-G02
- **执行步骤**：缺 `id`/`version`/`type`/`entry_points`/`declared_subsystems` 任一字段 → exit 1
- **预期结果**：JSON `{ok:false, gate:"plugin-schema", reasons:[...]}`
- **验收方法**：`[已有 bats]` `tests/m2-plugin-schema.bats`
- **优先级**：P0

#### AT-INSTALL-G03：plugin-id-validate
- **覆盖需求**：FR-PLUGIN-G03
- **执行步骤**：
  1. id `Foo`（首字母大写） → exit 1
  2. id `core` / `builtin` / `codenook` / `generic` （保留） → exit 1
  3. id 长度 < 3 / > 31 → exit 1
- **预期结果**：所有反例 exit 1；合规 `^[a-z][a-z0-9-]{2,30}$` exit 0
- **验收方法**：`[已有 bats]` `tests/m2-plugin-id-validate.bats`
- **优先级**：P0

#### AT-INSTALL-G04：plugin-version-check
- **覆盖需求**：FR-PLUGIN-G04
- **执行步骤**：非 SemVer (`1.x`) → exit 1；升级时 new ≤ old → exit 1
- **验收方法**：`[已有 bats]` `tests/m2-plugin-version-check.bats`
- **优先级**：P0

#### AT-INSTALL-G05：plugin-signature（默认可选 / 强制）
- **覆盖需求**：FR-PLUGIN-G05
- **执行步骤**：
  1. 默认（无 sig 文件） → exit 0
  2. `CODENOOK_REQUIRE_SIG=1` 且无 sig → exit 1
  3. 提供错误 sha256 → exit 1
  4. 提供正确 sha256（首 token 比对） → exit 0
- **验收方法**：`[已有 bats]` `tests/m2-plugin-signature.bats`
- **优先级**：P0

#### AT-INSTALL-G06：plugin-deps-check（SemVer AND 约束）
- **覆盖需求**：FR-PLUGIN-G06
- **执行步骤**：
  1. `requires.core_version: ">=0.10.0,<0.11.0"` 与 `--core-version 0.10.0` → exit 0
  2. core_version `0.9.0` → exit 1
- **验收方法**：`[已有 bats]` `tests/m2-plugin-deps-check.bats`
- **优先级**：P0

#### AT-INSTALL-G07：plugin-subsystem-claim 全局唯一
- **覆盖需求**：FR-PLUGIN-G07
- **执行步骤**：先安装 plugin A claim "podcast"；再安装 plugin B 也 claim "podcast" → exit 1
- **验收方法**：`[已有 bats]` `tests/m2-plugin-subsystem-claim.bats`
- **优先级**：P0

#### AT-INSTALL-G08：sec-audit（plugin source）
- **覆盖需求**：FR-PLUGIN-G08
- **执行步骤**：在 plugin 源植入 `sk-1234567890abcdef` → exit 1，severity=high
- **验收方法**：`[已有 bats]` `tests/m2-stage-source-security.bats`
- **优先级**：P0

#### AT-INSTALL-G09：size 限制（≤1MB / ≤10MB）
- **覆盖需求**：FR-PLUGIN-G09 / NFR-PERF-8
- **执行步骤**：
  1. 单文件 > 1MB → exit 1
  2. 总 > 10MB → exit 1
- **验收方法**：`[需新增 bats]`（目前由 install-orchestrator 内联，未独立 bats）
- **优先级**：P1

#### AT-INSTALL-G10：plugin-shebang-scan（仅 4 种允许）
- **覆盖需求**：FR-PLUGIN-G10 / FR-SEC-5
- **执行步骤**：
  1. shebang `#!/usr/bin/perl` → exit 1
  2. shebang `#!/usr/bin/env bash` → exit 0
  3. 允许集：`sh`, `bash`, `env bash`, `env python3`
- **验收方法**：`[已有 bats]` `tests/m2-plugin-shebang-scan.bats`
- **优先级**：P0

#### AT-INSTALL-G11：plugin-path-normalize（symlink/绝对/~/.. 全禁）
- **覆盖需求**：FR-PLUGIN-G11
- **执行步骤**：
  1. 含 symlink 任意类型 → exit 1
  2. yaml 含 `/abs/path` 或 `~/foo` 或 `../escape` → exit 1
- **验收方法**：`[已有 bats]` `tests/m2-plugin-path-normalize.bats`
- **优先级**：P0

#### AT-INSTALL-G12：atomic-commit（os.replace 提交）
- **覆盖需求**：FR-PLUGIN-G12
- **执行步骤**：
  1. 在 G12 commit 之前 SIGTERM orchestrator → 目标目录不出现半成品
  2. （手动）观察 staging dir 与最终 dir 的 inode 变化
- **验收方法**：`[手动]` + `[需新增 bats]`（中断测试不易自动化）
- **优先级**：P0


#### AT-MANIFEST-1：list_installed_ids 排序确定 + 损坏 tolerant
- **覆盖需求**：FR-PLUGIN-MANIFEST
- **前置条件**：装 3 个合法 plugin (id=alpha, beta, gamma) + 1 个损坏 manifest
- **执行步骤**：
  1. `python -c "from _lib.manifest_load import list_installed_ids as f; print(f('.scratch/ws-manifest'))"`
  2. `python -c "from _lib.plugin_manifest_index import discover_plugins as d; import json; print(json.dumps(d('.scratch/ws-manifest'), indent=2))"`
- **预期结果**：
  - 步骤 1 输出 `['alpha','beta','gamma']`（按 id 排序，损坏者跳过或 `_error`）
  - 步骤 2 损坏条目带 `_error` 字段，不抛异常
  - `intent_patterns` 缺失自动补 `[]`
- **验收方法**：`[已有 bats]` `tests/m2-manifest-load.bats` / `m8-plugin-manifest-index.bats`
- **优先级**：P0

---

### 3.3 TASK — 任务生命周期 / lock / chain 缓存

#### AT-TASK-1.1：state.json schema_version=1 必填字段齐全
- **覆盖需求**：FR-TASK-1
- **前置条件**：用 `make_task` helper 写 T-001
- **执行步骤**：
  1. `python -m jsonschema_lite skills/codenook-core/skills/_lib/schemas/task-state.schema.json .scratch/ws-task/.codenook/tasks/T-001/state.json`
  2. `jq '.schema_version, .task_id, .plugin, .phase, .iteration, .status' state.json`
- **预期结果**：
  - 退出码 0
  - 包含 schema_version/task_id/plugin/phase/iteration/max_iterations/status/history 全部必填
  - status ∈ {pending, in_progress, waiting_hitl, blocked, done, cancelled, error}
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`（间接断言）
- **优先级**：P0

#### AT-TASK-1.2：phase 白名单
- **覆盖需求**：FR-TASK-1
- **执行步骤**：写 phase=`bogus` → preflight exit 1
- **预期结果**：reason 含 "unknown phase"
- **验收方法**：`[已有 bats]` `tests/m1-preflight.bats`("task at unknown phase → exit 1")
- **优先级**：P1

#### AT-TASK-2.1：task_lock 互斥独占
- **覆盖需求**：FR-TASK-2 / NFR-REL-2
- **前置条件**：T-007 已存在
- **执行步骤**：
  1. 终端 A：`python -c "from _lib.task_lock import acquire; acquire('.scratch/ws/.codenook/tasks/T-007', 'A')"` 持锁
  2. 终端 B：相同 acquire → 5s 后 timeout → exit !=0
- **预期结果**：
  - A exit 0；payload 文件含 owner=A
  - B 抛 timeout / exit 非 0
- **验收方法**：`[已有 bats]` `tests/m8-task-lock.bats`
- **优先级**：P0

#### AT-TASK-2.2：stale lock 300s 后可被强制释放
- **覆盖需求**：FR-TASK-2 / §A.2 #3
- **执行步骤**：
  1. 持锁后 sleep 301（或 mock `time.time` 偏移）
  2. 调用 `inspect()` → 标记 stale
  3. `force_release()` → exit 0
  4. 不可解析 payload → 永不 unlink，仅 inspect 报错
- **预期结果**：见上
- **验收方法**：`[已有 bats]` `tests/m8-task-lock.bats`（"stale" 用例）+ `[手动]` 验证不可解析 payload
- **优先级**：P1

#### AT-TASK-3.1：task_chain 父子链 + chain_root 缓存
- **覆盖需求**：FR-TASK-3
- **前置条件**：build chain T-001(root) → T-002 → T-003
- **执行步骤**：
  1. `python -m _lib.task_chain set-parent --task T-002 --parent T-001 --workspace ws`
  2. `python -m _lib.task_chain show T-003 --format=json`
  3. `jq '.chain_root, .ancestors' out.json`
- **预期结果**：
  - chain_root=T-001
  - ancestors=["T-002","T-001"]
  - 链尾 detach 后，子节点 chain_root 重置为自身
  - 自环 set-parent T-002→T-002 → exit 1 + emit `chain_attach_failed`
- **验收方法**：`[已有 bats]` `tests/m10-task-chain.bats`
- **优先级**：P0

#### AT-TASK-3.2：max_depth=10 截断 + audit
- **覆盖需求**：FR-TASK-3 / §A.1 #2
- **执行步骤**：构造 depth=12 的链 → walk 应在 10 截断 + emit `chain_walk_truncated`
- **预期结果**：截断；audit 写一行 `kind=chain_walk_truncated`；调用 `max_depth=None` → 不截断（与 spec 文字"必有截断"边界差异 → PARTIAL）
- **验收方法**：`[已有 bats]` `tests/m10-task-chain.bats` + `[文档检查]`（标 PARTIAL）
- **优先级**：P1

#### AT-TASK-4.1：parent_suggester top-K + threshold + EN/ZH stopwords
- **覆盖需求**：FR-TASK-4 / §A.2 #2
- **前置条件**：5 个候选 task，brief 与其中 2 个高相似
- **执行步骤**：
  1. `python -m parent_suggester --workspace ws --brief "implement OAuth login" --top-k 3 --threshold 0.2`
  2. 用 `--exclude T-002` 排除
  3. mock LLM 模式可选：JSON 候选注入
- **预期结果**：
  - 输出 JSON `{candidates:[{task_id, score, reasons}]}`
  - score 范围 [0,1]，按 desc 排序
  - 排除项不出现
  - 内置停用词（约 70 词）从 token 集中剔除
- **验收方法**：`[已有 bats]` `tests/m10-parent-suggester.bats`
- **优先级**：P1

---

### 3.4 TICK — 单步推进引擎

#### AT-TICK-1.1：null phase 首发 dispatch
- **覆盖需求**：FR-TICK-1
- **前置条件**：T-100 phase=null, status=in_progress
- **执行步骤**：`bash .../orchestrator-tick/tick.sh --task T-100 --workspace ws --json`
- **预期结果**：
  - exit 0
  - phase 推进到首相位
  - in_flight_agent 被设
  - `dispatch.jsonl` 追加一行
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`("phase=null first dispatch...")
- **优先级**：P0

#### AT-TICK-1.2：output 未就绪 → status=waiting，状态不变
- **覆盖需求**：FR-TICK-1 / NFR-REL-1
- **执行步骤**：先 dispatch；不创建 output 文件；再 tick
- **预期结果**：status=waiting；phase / in_flight 不变；history 不追加
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`
- **优先级**：P0

#### AT-TICK-1.3：verdict=ok → 推进到下一 phase；verdict=needs_revision → 自循环
- **覆盖需求**：FR-TICK-1
- **执行步骤**：构造 output verdict=ok 与 needs_revision 两种 fixture
- **预期结果**：ok→next phase；revision→iteration+1；超过 max_iterations → status=blocked
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`
- **优先级**：P0

#### AT-TICK-1.4：HITL gate 触发 → status=waiting + hitl-queue 入队
- **覆盖需求**：FR-TICK-1
- **执行步骤**：phase.gate=hitl_required → tick
- **预期结果**：status=waiting；`.codenook/queues/hitl.jsonl` 追加一条
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`("HITL gate...")
- **优先级**：P0

#### AT-TICK-1.5：terminal status (done/cancelled/error) noop
- **覆盖需求**：FR-TICK-1
- **预期结果**：state 文件 mtime 不变；exit 0
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`
- **优先级**：P1

#### AT-TICK-1.6：fanout decomposed=true + 空 subtasks → blocked
- **覆盖需求**：FR-TICK-1
- **预期结果**：blocked；不伪造 child task
- **验收方法**：`[已有 bats]` `tests/m4-orchestrator-tick.bats`("decomposed=true + empty subtasks...")
- **优先级**：P1

#### AT-TICK-2.1：preflight 6 检查
- **覆盖需求**：FR-TICK-2 / FR-CTX-2
- **执行步骤**：构造 6 种缺陷的 task 各一份
- **预期结果**：exit 1；reasons 排序去重；输出含每项 reason
- **验收方法**：`[已有 bats]` `tests/m1-preflight.bats`
- **优先级**：P0

#### AT-TICK-2.2：preflight dual_mode 缺失 + max_iterations=1 → 通过（PARTIAL，§A.1 #1）
- **覆盖需求**：FR-TICK-2 / §A.1 #1
- **执行步骤**：max_iterations=1 且无 dual_mode → preflight exit 0
- **预期结果**：按 code → PASS；按 spec 严格"必填" → FAIL
- **验收方法**：`[已有 bats]` `tests/m1-preflight.bats` + 标 **PARTIAL**
- **优先级**：P1

#### AT-TICK-3.1：dispatch-audit 8-key + redact + 80 字符 preview
- **覆盖需求**：FR-TICK-3 / FR-EXTRACT-5 / NFR-OBS-4
- **执行步骤**：
  1. payload 含 `sk-proj-aaaaaaaaaaaaaaaaaaaaa` → emit
  2. `tail -1 .codenook/dispatch.jsonl | jq`
- **预期结果**：
  - 8 key 齐全（ts/task_id/plugin/kind/action/target/rationale/source）
  - secret 替换为 `[REDACTED]`
  - preview ≤ 80 char
- **验收方法**：`[已有 bats]` `tests/m4-dispatch-audit.bats`
- **优先级**：P0


---

### 3.5 ROUTER — 路由 / 上下文 / dispatch-build

#### AT-ROUTER-1.1：bootstrap 单一入口顺序：scan → select → dispatch-build
- **覆盖需求**：FR-ROUTER-1
- **执行步骤**：
  1. `bash .../router/bootstrap.sh --user-input "create podcast" --workspace ws --json > out.json`
  2. `jq '.target, .ranked_candidates' out.json`
- **预期结果**：
  - exit 0
  - target 是命中的 plugin id
  - dispatch.jsonl 末尾追加 `kind=router_dispatch_built`
  - 全程持有 `router.lock`
- **验收方法**：`[已有 bats]` `tests/m8-router-bootstrap.bats`
- **优先级**：P0

#### AT-ROUTER-1.2：router.lock 30s 超时 → exit 1
- **覆盖需求**：FR-ROUTER-1 / NFR-REL-2
- **执行步骤**：用 `m8_lock_holder.py` 持锁 60s；并发执行 router → timeout
- **预期结果**：exit 1；audit 记录 `lock_timeout`
- **验收方法**：`[已有 bats]` `tests/m8-router-bootstrap.bats`
- **优先级**：P1

#### AT-ROUTER-2.1：context-scan 输出 ≤2KB + 字段齐全
- **覆盖需求**：FR-CTX-1 / FR-ROUTER-2 / NFR-PERF-7
- **执行步骤**：`bash .../router-context-scan/scan.sh --workspace ws --max-tasks 5 --json | wc -c`
- **预期结果**：
  - exit 0
  - 字节数 ≤ 2048
  - JSON 含 `installed_plugins, active_tasks, hitl_pending, fanout_pending, workspace_warnings`
  - workspace > 100MB / >10K 文件 → 加 warning
- **验收方法**：`[已有 bats]` `tests/m8-router-context-scan.bats`
- **优先级**：P0

#### AT-ROUTER-2.2：缺 workspace → exit 2
- **覆盖需求**：FR-CTX-1
- **预期结果**：exit 2 + stderr 提示
- **验收方法**：`[已有 bats]` `tests/m8-router-context-scan.bats`
- **优先级**：P2

#### AT-ROUTER-3.1：select 评分 = keyword_hits×weight + priority + applies_to bonus
- **覆盖需求**：FR-ROUTER-3
- **执行步骤**：3 plugin 不同 priority/keyword → 用 select_with_score 验序
- **预期结果**：
  - 排序 desc
  - tie 时 lexicographic id
  - 全部 0 分 → fallback `__router__`
- **验收方法**：`[已有 bats]` `tests/m8-router-select.bats`
- **优先级**：P1

#### AT-ROUTER-4.1：dispatch-build payload ≤500B + role 谓词过滤
- **覆盖需求**：FR-ROUTER-4 / NFR-PERF-6
- **执行步骤**：
  1. 准备 role frontmatter 含 `included: [foo]` 与 `excluded: [bar]`
  2. `bash .../router-dispatch-build/build.sh --target foo --user-input "..." --json | wc -c`
- **预期结果**：
  - 字节数 ≤ 500
  - `--task` 缺则 `phase=null`
  - 不允许的 role 被过滤
- **验收方法**：`[已有 bats]` `tests/m8-router-dispatch-build.bats`
- **优先级**：P0

#### AT-ROUTER-5.1：router-agent draft 校验 + --confirm 落盘
- **覆盖需求**：FR-ROUTER-5
- **前置条件**：T-200 存在；mock LLM 返回合规 draft yaml
- **执行步骤**：
  1. `bash .../router-agent/spawn.sh --task-id T-200 --workspace ws --user-turn "build TODO app"`
  2. 输出 draft yaml；状态 needs_confirm
  3. `--confirm` 重跑 → 落盘 `tasks/T-200/draft-config.yaml`
- **预期结果**：
  - 缺必填字段 → exit 4
  - tier 非 _VALID_TIERS 之一 → exit 4
  - 解析错误也归 exit 4（PARTIAL，§A.1 #7）
  - --confirm 后 state.json.draft_confirmed=true
  - --user-turn-file `-` 读 stdin（A.2 #7）
- **验收方法**：`[已有 bats]` `tests/m8-router-agent.bats` + `[文档检查]` PARTIAL
- **优先级**：P0

---

### 3.6 CHAIN — 链路 / snapshot / summarize

#### AT-CHAIN-1.1：snapshot 增量重建
- **覆盖需求**：FR-CHAIN-1 / NFR-PERF-3 / NFR-PERF-4
- **前置条件**：50 个 task 的链
- **执行步骤**：
  1. 删除 `.chain-snapshot.json`
  2. `python -m _lib.task_chain rebuild --workspace ws`
  3. `time python -m _lib.task_chain show <leaf>`（warm）
  4. mtime 变更一个 state.json → rebuild → 应增量
- **预期结果**：
  - schema_version=1，含 generation 单调递增
  - warm 命中 < 5ms
  - chain_root 与逐个 walk 结果一致
- **验收方法**：`[已有 bats]` `tests/m10-chain-snapshot.bats`
- **优先级**：P0

#### AT-CHAIN-2.1：chain_summarize 两 pass + token 预算
- **覆盖需求**：FR-CHAIN-2 / NFR-OBS-3
- **前置条件**：mock LLM `chain_summarize.txt`
- **执行步骤**：
  1. `python -m _lib.chain_summarize --task <leaf> --workspace ws`
  2. 验输出含 `summary, ancestors_summary[]`
- **预期结果**：
  - 每条祖先 summary 由 token_estimate 控制 ≤ 预算
  - LLM 失败仅写一次 audit 不重试（L-7）
- **验收方法**：`[已有 bats]` `tests/m10-chain-summarize.bats`
- **优先级**：P1

#### AT-CHAIN-3.1：router slot CHAIN_SUMMARY 注入
- **覆盖需求**：FR-CHAIN-3
- **执行步骤**：dispatch-build 时该 task 有 parent → payload 含 `chain.summary`
- **预期结果**：payload 仍 ≤ 500B；summary 截断保结构
- **验收方法**：`[已有 bats]` `tests/m10-router-chain-slot.bats`
- **优先级**：P1

#### AT-CHAIN-4.1：parent_suggest_skip audit
- **覆盖需求**：FR-CHAIN-4
- **执行步骤**：用户拒绝 suggester top-1 → emit `parent_suggest_skip`
- **预期结果**：audit 行 kind=parent_suggest_skip，含被跳过 candidate
- **验收方法**：`[已有 bats]` `tests/m10-parent-suggester.bats`
- **优先级**：P2

#### AT-CHAIN-5.1：chain_attached / chain_root_stale 4 类 audit
- **覆盖需求**：FR-CHAIN-5 / NFR-OBS-3
- **执行步骤**：
  1. set-parent → emit `chain_attached`
  2. mtime 偏移导致 chain_root 失效 → walk 时 emit `chain_root_stale`
  3. snapshot rebuild > 阈值 → emit `chain_snapshot_slow_rebuild`
  4. 自环 attach → emit `chain_attach_failed`
- **预期结果**：四类 audit 行均符合 8-key
- **验收方法**：`[已有 bats]` `tests/m10-task-chain.bats` + `m10-chain-snapshot.bats`
- **优先级**：P1

---

### 3.7 MEM — 内存层 / 索引 / GC

#### AT-MEM-1.1：knowledge / skills / config 三类写入 + atomic + flock
- **覆盖需求**：FR-MEM-1 / NFR-REL-1 / NFR-REL-2
- **执行步骤**：
  1. `python -c "from _lib.memory_layer import write_knowledge; write_knowledge(ws, 'topic', summary='x'*200, tags=['a']*8, content='ok')"`
  2. summary 201 char → ValueError
  3. tags 9 个 → ValueError
  4. topic `bad/path` → ValueError
- **预期结果**：合规写入成功；非法皆抛错
- **验收方法**：`[已有 bats]` `tests/m9-memory-layer.bats`
- **优先级**：P0

#### AT-MEM-1.2：写入插件子树 → PluginReadOnlyViolation
- **覆盖需求**：FR-MEM-1 / FR-SKILL-2 / NFR-SEC-1
- **执行步骤**：尝试 write_knowledge 路径在 `.codenook/plugins/<id>/...`
- **预期结果**：抛 PluginReadOnlyViolation；emit audit kind=`plugin_readonly_violation`
- **验收方法**：`[已有 bats]` `tests/m9-plugin-readonly.bats`
- **优先级**：P0

#### AT-MEM-2.1：memory_index 冷构建 < 500ms / warm < 200ms
- **覆盖需求**：FR-MEM-2 / NFR-PERF-1 / NFR-PERF-2
- **前置条件**：1000 个 markdown fixture
- **执行步骤**：
  1. 删 snapshot；`time python -c "from _lib.memory_index import build_index; build_index(ws)"`（cold）
  2. 不变文件再 build（warm）
- **预期结果**：cold p95 < 500ms；warm < 200ms；mtime/size 一致跳过解析
- **验收方法**：`[已有 bats]` `tests/m9-memory-index.bats`（性能仅 smoke；P3 用 `time` 复核）
- **优先级**：P1

#### AT-MEM-2.2：invalidate 单条 + 并发 flock
- **覆盖需求**：FR-MEM-2
- **执行步骤**：两进程同时写不同 path → 不死锁；快照单条失效不影响其他
- **验收方法**：`[已有 bats]` `tests/m9-memory-index.bats`
- **优先级**：P1

#### AT-MEM-3.1：8-key audit schema + 子事件 kind
- **覆盖需求**：FR-MEM-3 / NFR-OBS-1 / NFR-OBS-2
- **执行步骤**：
  1. 触发各 extractor 各 1 次
  2. `jq -c '. | keys' .codenook/extraction-log.jsonl | sort -u`
- **预期结果**：
  - 每行 8 key 齐全
  - 缺 key → extract_audit 抛错
  - kind 覆盖 `knowledge_proposed/skill_promoted/config_patched/gc_pruned/chain_attached/parent_suggest_skip` 等
  - 全 append-only（先记 mtime 再追加，size 单调增）
- **验收方法**：`[已有 bats]` `tests/m9-extract-audit.bats`
- **优先级**：P0

#### AT-MEM-4.1：memory_gc caps（k≤3, s≤1, c≤5）+ promoted 跳过
- **覆盖需求**：FR-MEM-4 / §A.2 #4
- **执行步骤**：
  1. 同 task 写 5 条 knowledge
  2. `python -m memory_gc --workspace ws`
  3. 标 `promoted=true` 一条 → 重跑 gc，该条不被淘汰
- **预期结果**：
  - 留 3 条最新；2 条 emit `gc_pruned`
  - promoted 永留
  - rebuild snapshot 一次
  - exit 0/1/2 三态
- **验收方法**：`[已有 bats]` `tests/m9-memory-gc.bats`
- **优先级**：P0


---

### 3.8 EXTRACT — 抽取流水线

#### AT-EXTRACT-1.1：knowledge-extractor secret-blocked → 非 0
- **覆盖需求**：FR-EXTRACT-1 / NFR-REL-3
- **前置条件**：phase log 含 `sk-1234567890abcdef`
- **执行步骤**：`bash .../knowledge-extractor/extract.sh --task T-300 --workspace ws --phase implement --reason after_phase`
- **预期结果**：exit 非 0；audit kind=`extract_blocked_secret`；不写 knowledge 文件
- **验收方法**：`[已有 bats]` `tests/m9-knowledge-extractor.bats`
- **优先级**：P0

#### AT-EXTRACT-1.2：normal best-effort exit 0 + ≤3 条 cap
- **覆盖需求**：FR-EXTRACT-1
- **执行步骤**：mock LLM 返 5 条 → 只留 3
- **预期结果**：exit 0；写 3 条到 `.codenook/memory/by-topic/` 或 `<plugin>/by-topic/`
- **验收方法**：`[已有 bats]` `tests/m9-knowledge-extractor.bats`
- **优先级**：P0

#### AT-EXTRACT-2.1：skill-extractor ≥3 重复 shell → 1 候选
- **覆盖需求**：FR-EXTRACT-2
- **执行步骤**：phase log 重复 `git status` ≥3 次
- **预期结果**：exit 0；写 `.codenook/skills/{custom,task}/<name>/SKILL.md`；per-task cap=1
- **验收方法**：`[已有 bats]` `tests/m9-skill-extractor.bats`
- **优先级**：P1

#### AT-EXTRACT-3.1：config-extractor ≥2 KEY=VALUE → patch
- **覆盖需求**：FR-EXTRACT-3
- **执行步骤**：phase log 含 `MODEL=opus FOO=bar`
- **预期结果**：exit 0；emit `config_patched`；cap=5
- **验收方法**：`[已有 bats]` `tests/m9-config-extractor.bats`
- **优先级**：P1

#### AT-EXTRACT-4.1：extractor-batch fan-out 三抽取并行 + 幂等
- **覆盖需求**：FR-EXTRACT-4 / NFR-REL-4
- **执行步骤**：
  1. `bash .../extractor-batch/extractor-batch.sh --task T-400 --reason after_phase`
  2. 立即重跑（同 key）
  3. `--reason context-pressure` 重跑
- **预期结果**：
  - 第 1 次三抽取均派发（nohup detached，§A.2 #9）
  - 第 2 次 → `skipped: [...]`
  - 第 3 次（不同 reason）→ 重新派发
  - 任一 extractor 失败不影响其他
- **验收方法**：`[已有 bats]` `tests/m9-extractor-batch.bats`
- **优先级**：P0

#### AT-EXTRACT-4.2：幂等窗口 24h（PARTIAL，§A.1 #4）
- **覆盖需求**：FR-EXTRACT-4 / §A.1 #4
- **执行步骤**：相同 key 在 25h 后重跑（伪造 audit ts）
- **预期结果**：当前实现 → 永久幂等（PARTIAL，按 code 验）
- **验收方法**：`[需新增 bats]` + 标 **PARTIAL**
- **优先级**：P2

#### AT-EXTRACT-5.1：dispatch-audit 9 类 secret redact
- **覆盖需求**：FR-EXTRACT-5 / FR-SEC-2 / NFR-OBS-4
- **执行步骤**：分别构造 `sk-`, `sk-proj-`, `sk-ant-`, `sk-ant-api03-`, `AKIA`, `ghp_`, `gho_`, `github_pat_`, PEM 头 9 类样本 emit
- **预期结果**：每类皆替换为 `[REDACTED]`（PARTIAL：spec 部分处提"10 类"，实际 9 类，§A.1 #5）
- **验收方法**：`[已有 bats]` `tests/m9-dispatch-audit-redact.bats` + 标 **PARTIAL**
- **优先级**：P0

---

### 3.9 DIST — distiller 表达式归档

#### AT-DIST-1.1：表达式真 → workspace；全假 → plugin 私域
- **覆盖需求**：FR-DIST-1 / §A.2 #8
- **执行步骤**：
  1. plugin.yaml 配 `promote_to_workspace_when: ["score >= 0.8"]`，content score=0.9 → workspace
  2. score=0.5 → plugin 私域
- **预期结果**：
  - 路径分别落在 `.codenook/knowledge/` vs `.codenook/memory/<plugin>/`
  - `distillation-log.jsonl` 追加一行
  - 表达式含 `__` 或 `import` → exit 1（sandbox 禁用）
- **验收方法**：`[已有 bats]` `tests/m9-distiller.bats`
- **优先级**：P1

#### AT-DIST-1.2：非法表达式语法 → exit 1
- **覆盖需求**：FR-DIST-1
- **预期结果**：stderr 含语法错误位置
- **验收方法**：`[已有 bats]` `tests/m9-distiller.bats`
- **优先级**：P2

---

### 3.10 SKILL & PLUGIN

#### AT-SKILL-1.1：4-tier skill 解析顺序
- **覆盖需求**：FR-SKILL-1 / NFR-EXT-2
- **前置条件**：同名 skill 同时存在四层
- **执行步骤**：`bash .../skill-resolve/resolve-skill.sh --name foo --plugin pX --workspace ws --json`
- **预期结果**：
  - tier=plugin_local（最高优先）
  - 删除该层后 → plugin_shipped
  - 再删 → workspace_custom → builtin
  - --name 含 `/` `..` 非法字符 → exit 2
  - 找不到 → exit 1 + candidates 列表
- **验收方法**：`[已有 bats]` `tests/m8-skill-resolve.bats`
- **优先级**：P0

#### AT-SKILL-2.1：plugin_readonly 静态扫
- **覆盖需求**：FR-SKILL-2 / §A.2 #1
- **执行步骤**：
  1. 在 plugin 源植入 `open(path,'w')` 写 `.codenook/plugins/...`
  2. `python skills/codenook-core/skills/_lib/plugin_readonly.py --target tests/fixtures/m9-plugin-readonly --json`
- **预期结果**：
  - exit 1
  - 报告命中 open / write_text / shutil.copy*
  - 默认排除 test fixture
  - exit 0/1/2 三态
- **验收方法**：`[已有 bats]` `tests/m9-plugin-readonly.bats`
- **优先级**：P0

#### AT-ROLE-1.1：role frontmatter 必填 + include/exclude 谓词
- **覆盖需求**：FR-ROLE-1
- **执行步骤**：
  1. role.md 缺 `phase` → discover_roles 报错
  2. constraints `included:[a]` + `excluded:[b]` → is_role_allowed('a')=True，('b')=False，('c')=False
  3. constraints 空 → 所有 role 允许
- **验收方法**：`[已有 bats]` `tests/m8-role-index.bats`
- **优先级**：P1

---

### 3.11 CONFIG — 4 层合并 / mutator / validate

#### AT-CONFIG-1.1：deep-merge + _provenance + 白名单
- **覆盖需求**：FR-CONFIG-1 / NFR-EXT-3
- **执行步骤**：
  1. 4 层各放 `models.executor`
  2. `bash .../config-resolve/resolve.sh --plugin foo --workspace ws --task T-1 --catalog cat.json | jq '._provenance'`
- **预期结果**：
  - 最高优先 task layer 胜出
  - `_provenance.models.executor.from_layer="task"`
  - 未知 top-key（如 `evil:`） → exit 1
  - 兜底 strong→balanced→cheap→opus-4.7（§A.2 #5）
- **验收方法**：`[已有 bats]` `tests/m4-config-resolve.bats`
- **优先级**：P0

#### AT-CONFIG-2.1：tier 符号展开 + catalog miss → fallback
- **覆盖需求**：FR-CONFIG-2 / §A.2 #5
- **执行步骤**：
  1. tier_strong 在 catalog 存在 → resolved_via=catalog
  2. catalog 缺 tier_strong → resolved_via=fallback
  3. catalog 全损坏 → resolved_via=hardcoded，stderr 警告
- **预期结果**：`_provenance.symbol="tier_strong"`；最末兜底 `claude-opus-4.7`
- **验收方法**：`[已有 bats]` `tests/m5-model-probe.bats` + `tests/m4-config-resolve.bats`
- **优先级**：P0

#### AT-CONFIG-3.1：config-mutator workspace / task 写入 + history
- **覆盖需求**：FR-CONFIG-3
- **执行步骤**：
  1. `bash .../config-mutator/mutate.sh --plugin foo --path models.executor --value tier_strong --reason test --actor user --workspace ws`
  2. 同值再写 → 不写 history（no-op）
  3. 路径 `_secret` 或 `..` → exit 1
  4. actor=hitl OK；actor=evil → exit 1
  5. plugin=`__router__` 改 `models.router` → exit 1
- **预期结果**：
  - history/config-changes.jsonl 各行有 8 key
  - 写入走 atomic
- **验收方法**：`[已有 bats]` `tests/m4-config-mutator.bats`
- **优先级**：P0

#### AT-CONFIG-4.1：task-config-set 简写
- **覆盖需求**：FR-CONFIG-4
- **执行步骤**：
  1. `set.sh --task T-500 --key models.executor --value tier_strong`
  2. `set.sh --task T-500 --key models.executor --unset`
  3. key 不在白名单 → exit 1
- **预期结果**：state.json.config_overrides 同步；--unset 删 key
- **验收方法**：`[已有 bats]` `tests/m4-task-config-set.bats`
- **优先级**：P1

#### AT-CONFIG-5.1：config-validate types/ranges/enums
- **覆盖需求**：FR-CONFIG-5
- **执行步骤**：
  1. 类型错误 → errors 非空 exit 1
  2. deprecated key → warnings 非空 exit 0
  3. `--json` 输出 schema
- **验收方法**：`[已有 bats]` `tests/m4-config-validate.bats`
- **优先级**：P1

#### AT-CONFIG-6.1：draft_config 必填 + tier 白名单
- **覆盖需求**：FR-CONFIG-6
- **执行步骤**：python 单测：缺 `models.default` → ValueError；tier=`tier_evil` → ValueError；YAML dumps 排序稳定（`diff` 两次）
- **验收方法**：`[已有 bats]` `tests/m8-draft-config.bats`
- **优先级**：P1


---

### 3.12 LLM — 调用 / mock / token

#### AT-LLM-1.1：4 档 mock 解析顺序
- **覆盖需求**：FR-LLM-1 / NFR-EXT-1
- **执行步骤**：
  1. 仅设 `CN_LLM_MOCK_RESPONSE` → 兜底
  2. 加 `CN_LLM_MOCK_FOO` → 覆盖
  3. 加 `CN_LLM_MOCK_FILE` → 覆盖
  4. 加 `CN_LLM_MOCK_DIR/foo.json` → 最高优先
  5. 全无 → fallback `[mock-llm:foo] <prompt[:80]>`
- **预期结果**：每步返回值与该档一致
- **验收方法**：`[已有 bats]` `tests/m9-llm-mock.bats`
- **优先级**：P0

#### AT-LLM-2.1：real-mode 安全护栏（无密钥时）
- **覆盖需求**：FR-LLM-2
- **执行步骤**：缺 `OPENAI_API_KEY` 调用 → exit 非 0；不写 partial response
- **预期结果**：明确报错，提示如何注入
- **验收方法**：`[需新增 bats]`（real-mode 默认 mock；护栏路径未单测）
- **优先级**：P2

#### AT-LLM-3.1：token_estimate 字数预算
- **覆盖需求**：FR-LLM-3
- **执行步骤**：单测 `estimate("一二三") == ~3` 等
- **验收方法**：`[已有 bats]` `tests/m9-token-estimate.bats`
- **优先级**：P2

---

### 3.13 SEC — 安全栈

#### AT-SEC-1.1：secret_scan 9 patterns fail-close
- **覆盖需求**：FR-SEC-1 / §A.1 #5
- **执行步骤**：分别构造 9 类 secret 字符串调用 `scan_secrets()`
- **预期结果**：9 类全命中；redact() 用 `[REDACTED]` 替换；与 spec "10 类" 描述差异 → PARTIAL
- **验收方法**：`[已有 bats]` `tests/m9-secret-scan.bats` + 标 **PARTIAL**
- **优先级**：P0

#### AT-SEC-2.1：sec-audit 阻断 high
- **覆盖需求**：FR-SEC-2
- **执行步骤**：plugin 源含 high severity → install exit 1
- **验收方法**：`[已有 bats]` `tests/m2-stage-source-security.bats`
- **优先级**：P0

#### AT-SEC-3.1：secrets-resolve env 注入 + redact
- **覆盖需求**：FR-SEC-3
- **执行步骤**：plugin 配 `secrets.required: ["FOO"]`；导出 `FOO=bar`
- **预期结果**：exit 0；audit 记录 `secret_resolved name=FOO value=[REDACTED]`；缺 → exit 1
- **验收方法**：`[已有 bats]` `tests/m3-secrets-resolve.bats`
- **优先级**：P0

#### AT-SEC-4.1：claude_md_linter 4 类 violation
- **覆盖需求**：FR-SEC-4
- **执行步骤**：
  1. CLAUDE.md 写绝对模型 ID `gpt-4o` → high
  2. 写 `cd /` → high
  3. 写 `xxx-of-record` → medium
  4. broken markdown link → low
- **预期结果**：`--strict` exit 1；JSON 报告含分类
- **验收方法**：`[已有 bats]` `tests/m9-claude-md-linter.bats`
- **优先级**：P1

#### AT-SEC-5.1：plugin-shebang-scan 仅 4 种
- **覆盖需求**：FR-SEC-5
- **见**：AT-INSTALL-G10
- **优先级**：P0

---

### 3.14 QUEUE / SESS / HITL

#### AT-QUEUE-1.1：queue-runner status / drain
- **覆盖需求**：FR-QUEUE-1
- **执行步骤**：
  1. 写 3 条 `.codenook/queues/hitl.jsonl`
  2. `bash .../queue-runner/runner.sh --status --json`
  3. `... --drain --max 2`
- **预期结果**：
  - status 显示 3 条 pending
  - drain 处理 2 条 → exit 0
  - jsonl 损坏单行 → 跳过 + audit kind=`queue_corrupt_line`
- **验收方法**：`[已有 bats]` `tests/m6-queue-runner.bats`
- **优先级**：P1

#### AT-SESS-1.1：session-resume snapshot ≤2KB + M1-compat keys
- **覆盖需求**：FR-SESS-1 / §A.2 #6
- **执行步骤**：`bash .../session-resume/resume.sh --workspace ws --json | wc -c`
- **预期结果**：
  - ≤ 2048 字节
  - 含 v6 字段 + M1-compat (`active_task, phase, iteration, summary, hitl_pending, next_suggested_action, last_action_ts, total_iterations`)
  - 路由调用注入到上下文首段
- **验收方法**：`[已有 bats]` `tests/m6-session-resume.bats`
- **优先级**：P1

#### AT-HITL-1.1：hitl-adapter blocking + ledger 单独 lock
- **覆盖需求**：FR-HITL-1
- **执行步骤**：
  1. `bash .../hitl-adapter/adapter.sh --task T-600 --kind clarify --message "?" --workspace ws --json &`
  2. 同时另一进程对同 task hitl-adapter → 阻塞
  3. user 回复 → resolve；emit `hitl_resolved`
- **预期结果**：单 task 串行；ledger 一致；timeout → exit 非 0
- **验收方法**：`[已有 bats]` `tests/m6-hitl-adapter.bats`
- **优先级**：P1

---

### 3.15 CTX — 上下文与 preflight

#### AT-CTX-1.1 / AT-CTX-2.1
- 已映射到 AT-ROUTER-2.1（context-scan）与 AT-TICK-2.1（preflight 6 检查）。


---

## 4. 非功能验收

### 4.1 性能验收

| AT-ID | 覆盖 NFR | 场景 | 命令 | 预期 | 优先级 |
|-------|---------|------|------|------|-------|
| AT-PERF-1 | NFR-PERF-1 | memory_index cold 1k md | `time python -c "from _lib.memory_index import build_index; build_index(ws)"` | p95 < 500ms | P1 |
| AT-PERF-2 | NFR-PERF-2 | memory_index warm | 同上重跑 | p95 < 200ms | P1 |
| AT-PERF-3 | NFR-PERF-3 | chain snapshot rebuild 1k task | `time python -m _lib.task_chain rebuild` | < 800ms（超阈 emit `chain_snapshot_slow_rebuild`）| P1 |
| AT-PERF-4 | NFR-PERF-4 | chain warm hit 50 深 | `time python -m _lib.task_chain show <leaf>` | < 5ms | P1 |
| AT-PERF-5 | NFR-PERF-5 | router context-scan 100 task | `time bash router-context-scan/scan.sh` | < 200ms | P1 |
| AT-PERF-6 | NFR-PERF-6 | dispatch-build payload | `wc -c` | ≤ 500 B | P0 |
| AT-PERF-7 | NFR-PERF-7 | router-context payload | `wc -c` | ≤ 2 KB | P0 |
| AT-PERF-8 | NFR-PERF-8 | install size cap | `du -sb` plugin | 单文件 ≤ 1MB；总 ≤ 10MB | P1 |

> 性能 AT 在 macOS 单机 M1/M2 + Python 3.11 基线上验收；CI 中允许 ×1.5 容差。

### 4.2 可靠性验收

| AT-ID | 覆盖 NFR | 场景 | 验证 | 优先级 |
|-------|---------|------|------|-------|
| AT-REL-1 | NFR-REL-1 | atomic write 中断 | 在 `tempfile + os.replace` 之间 SIGTERM；无半成品 | P0（手动） |
| AT-REL-2 | NFR-REL-2 | flock 互斥 | 见 AT-TASK-2.1, AT-ROUTER-1.2, AT-MEM-1.1 | P0 |
| AT-REL-3 | NFR-REL-3 | extractor secret fail-close | 见 AT-EXTRACT-1.1 | P0 |
| AT-REL-4 | NFR-REL-4 | extractor 24h 幂等 | 见 AT-EXTRACT-4.1（PARTIAL → 见 §6） | P1 |
| AT-REL-5 | NFR-REL-5 | install 整体回滚 | 见 AT-INSTALL-1.2, AT-INSTALL-G12 | P0 |

### 4.3 可观测性验收

| AT-ID | 覆盖 NFR | 场景 | 命令 | 优先级 |
|-------|---------|------|------|-------|
| AT-OBS-1 | NFR-OBS-1 | 8-key schema | `jq -e 'keys==["action","kind","plugin","rationale","source","target","task_id","ts"]'` 全行 | P0 |
| AT-OBS-2 | NFR-OBS-2 | extraction-log append-only | 监测 inode + size 单调；append 只 | P0 |
| AT-OBS-3 | NFR-OBS-3 | chain audit 4 类 | 见 AT-CHAIN-5.1 | P1 |
| AT-OBS-4 | NFR-OBS-4 | dispatch redact + ≤80B preview | 见 AT-TICK-3.1, AT-EXTRACT-5.1 | P0 |

### 4.4 安全验收

| AT-ID | 覆盖 NFR | 场景 | 优先级 |
|-------|---------|------|-------|
| AT-SEC-NFR-1 | NFR-SEC-1 | plugin readonly 静态扫 | 见 AT-SKILL-2.1 | P0 |
| AT-SEC-NFR-2 | NFR-SEC-2 | secret 9 patterns redact | 见 AT-SEC-1.1, AT-EXTRACT-5.1（PARTIAL） | P0 |
| AT-SEC-NFR-3 | NFR-SEC-3 | shebang 4 种 | 见 AT-INSTALL-G10 | P0 |
| AT-SEC-NFR-4 | NFR-SEC-4 | path normalize 全禁 | 见 AT-INSTALL-G11 | P0 |
| AT-SEC-NFR-5 | NFR-SEC-5 | claude_md_linter | 见 AT-SEC-4.1 | P1 |

### 4.5 跨平台

| AT-ID | 覆盖 NFR | 场景 | 备注 | 优先级 |
|-------|---------|------|------|-------|
| AT-COMPAT-1 | NFR-COMPAT-1 | macOS 13+ / Ubuntu 22.04 全用例 | CI matrix 双跑 | P1 |
| AT-COMPAT-2 | NFR-COMPAT-2 | Windows = unsupported | 文档检查 README + init 启动横幅 | P2（文档） |
| AT-COMPAT-3 | NFR-COMPAT-3 | jq / python3 缺失诊断 | 卸载 jq → init 给出明确报错 | P2 |

### 4.6 可扩展验收

| AT-ID | 覆盖 NFR | 场景 | 优先级 |
|-------|---------|------|-------|
| AT-EXT-1 | NFR-EXT-1 | LLM mock 协议 4 档 | 见 AT-LLM-1.1 | P0 |
| AT-EXT-2 | NFR-EXT-2 | 4-tier skill 解析 | 见 AT-SKILL-1.1 | P0 |
| AT-EXT-3 | NFR-EXT-3 | 4 层 config 合并 + provenance | 见 AT-CONFIG-1.1 | P0 |

---

## 5. 端到端场景验收

> 每个 E2E 至少串联 ≥3 个 skill；fixture 建议放 `tests/fixtures/e2e-v010/`。
> 现有 e2e bats：`tests/e2e/m9-e2e.bats`（已覆盖 E2E-01 部分流程）。

### AT-E2E-01：从空仓库到第一次 dispatch
- **覆盖需求**：FR-INIT-1, FR-ROUTER-1..5, FR-TICK-1, FR-EXTRACT-4
- **优先级**：P0
- **执行步骤**：
  1. `init.sh .scratch/ws-e2e-1`
  2. `router/bootstrap.sh --user-input "create podcast for X"` → 拿 target
  3. `router-agent/spawn.sh --task-id T-E1 ... --confirm` → draft 落盘
  4. `orchestrator-tick/tick.sh --task T-E1` → 首 phase dispatch
  5. mock phase output → 再 tick → next phase
  6. 完成最末 phase → status=done + extractor-batch 派发
- **预期结果**：
  - 全程退出码 0
  - state.json schema_version=1，phase 进入 done
  - extraction-log.jsonl 至少含 `dispatch, knowledge_proposed, distill` 各 1
  - dispatch.jsonl 全行 8-key
- **验收方法**：`[已有 bats]` 部分覆盖 (`tests/e2e/m9-e2e.bats`) + `[需新增 bats]` v0.10 完整链路

### AT-E2E-02：父子链 + chain summary 注入
- **覆盖需求**：FR-CHAIN-1..5, FR-TASK-3..4
- **优先级**：P0
- **执行步骤**：
  1. 装好 plugin、create T-E2-root 并跑 1 phase
  2. `parent_suggester` 推荐；`task_chain set-parent --task T-E2-child --parent T-E2-root`
  3. `chain_summarize`
  4. router-dispatch-build → CHAIN_SUMMARY 注入
  5. detach；rebuild snapshot
- **预期结果**：summary 注入；4 类 audit 出现；snapshot 增量；payload ≤ 500B
- **验收方法**：`[需新增 bats]` （现有按里程碑分散）

### AT-E2E-03：HITL 阻塞 → resume → tick 推进
- **覆盖需求**：FR-HITL-1, FR-QUEUE-1, FR-SESS-1
- **优先级**：P1
- **执行步骤**：
  1. tick 触发 hitl gate → status=waiting
  2. queue-runner status 看到 1 条 pending
  3. hitl-adapter 完成 → emit `hitl_resolved`
  4. session-resume snapshot
  5. 再 tick → 继续推进
- **预期结果**：snapshot 含恢复后 next_suggested_action；ledger 单调
- **验收方法**：`[需新增 bats]`

### AT-E2E-04：install-orchestrator 失败回滚
- **覆盖需求**：FR-INSTALL-1, FR-PLUGIN-G01..G12, NFR-REL-5
- **优先级**：P0
- **执行步骤**：
  1. 准备一个 G07 冲突 plugin
  2. 安装 → exit 1
  3. ls `.codenook/plugins/` 不出现该 id
  4. state.json.installed_plugins 不变
- **预期结果**：原子失败；audit 记录失败 gate
- **验收方法**：`[已有 bats]` `tests/m2-install-orchestrator.bats` 覆盖单 gate；`[需新增 bats]` 覆盖完整 12 gate fail-fast 流

### AT-E2E-05：抽取闭环（knowledge / skill / config）
- **覆盖需求**：FR-EXTRACT-1..5, FR-MEM-1..4, FR-DIST-1
- **优先级**：P1
- **执行步骤**：
  1. tick 完成一个 phase
  2. extractor-batch dispatch 三抽取 + distiller
  3. memory_gc
  4. extraction-log.jsonl 含 6 类 kind
- **预期结果**：知识 caps 生效；promoted 跳过；distiller 表达式判路
- **验收方法**：`[已有 bats]` `tests/m9-extractor-batch.bats` + `[需新增 bats]` 跨 5 sub-system 闭环


---

## 6. 已知不一致 / 缺漏的验收处理

> 来源：SRS §A.1（8 条 spec/code 不一致）+ §A.2（10 条 spec 缺漏）
> 决策原则：**v0.10 验收以 code 实际行为为准（PASS/PARTIAL）**，不一致项标 PARTIAL 并在 §7 备注列引用本节编号。

### 6.1 §A.1 不一致项

| 编号 | 主题 | 关联 AT | 是否纳入 | 验收基准 | PARTIAL 风险 |
|------|------|--------|---------|---------|------------|
| A1-1 | dual_mode 缺省视为 serial | AT-TICK-2.2 | ✅ | code | **PARTIAL**：spec 未明文，需 spec patch |
| A1-2 | chain max_depth=None 不截断 | AT-TASK-3.2 | ✅ | code | **PARTIAL**：边界与 spec "必有截断" 叙述不符 |
| A1-3 | plugin.yaml.sig 宽松对比（first non-blank token） | AT-INSTALL-G05 | ✅ | code | **PARTIAL**：spec 未说明宽松规则 |
| A1-4 | extractor 24h 幂等实为永久 | AT-EXTRACT-4.2 | ✅ | code | **PARTIAL**：未实现轮转，PARTIAL 计入 |
| A1-5 | secret patterns 实为 9 条非 10 | AT-SEC-1.1, AT-EXTRACT-5.1 | ✅ | code | **PARTIAL**：文档误写"10 条" |
| A1-6 | session-resume 保留 M1-compat keys | AT-SESS-1.1 | ✅ | code | **PARTIAL**：v6 spec 已 greenfield，仍保留 |
| A1-7 | router-agent --confirm exit 4 含解析错误 | AT-ROUTER-5.1 | ✅ | code | **PARTIAL**：spec exit 枚举粒度不足 |
| A1-8 | G01 vs G11 symlink 策略差异 | AT-INSTALL-G01, AT-INSTALL-G11 | ✅ | code | **PARTIAL**：双闸门差异未明记 |

PARTIAL 用例总计：**8** 条（与 §A.1 一一对应）。

### 6.2 §A.2 spec 缺漏项（code 已实现）

| 编号 | 主题 | 关联 AT | 是否纳入 | 备注 |
|------|------|--------|---------|------|
| A2-1 | plugin_readonly 静态 CLI + 默认排除 fixture | AT-SKILL-2.1 | ✅ | 验收按 code（PASS） |
| A2-2 | parent_suggester 内置 ~70 EN+ZH stopwords | AT-TASK-4.1 | ✅ | 验收按 code |
| A2-3 | task_lock stale 300s + 不可解析 payload 永不删 | AT-TASK-2.2 | ✅ | 不可解析 payload 用例 `[手动]` |
| A2-4 | memory_gc promoted=true 永不淘汰 | AT-MEM-4.1 | ✅ | 验收按 code |
| A2-5 | config-resolve 兜底链硬编码 strong→balanced→cheap→opus-4.7 | AT-CONFIG-2.1 | ✅ | 验收按 code |
| A2-6 | dispatch-audit redaction 9 类清单 | AT-EXTRACT-5.1 | ✅ | 验收按 code |
| A2-7 | router-agent --user-turn-file `-` 读 stdin | AT-ROUTER-5.1 | ✅ | 验收按 code |
| A2-8 | distiller sandbox 禁 `__` / `import` | AT-DIST-1.1 | ✅ | 验收按 code |
| A2-9 | extractor-batch nohup 派发 | AT-EXTRACT-4.1 | ✅ | 验收按 code |
| A2-10 | plugin_manifest_index DEFAULT_PRIORITY=100 | AT-MANIFEST-1 | ✅ | 验收按 code |

§A.2 不计入 PARTIAL（功能存在且可断言）；仅作为 spec patch 待办。

### 6.3 总 PARTIAL 风险

- **PARTIAL 用例数**：8（A1-1..A1-8 各 1）
- **建议处理**：
  1. v0.11 同步发 spec patch 闭合 A.1；
  2. 验收报告中显式列出每条 PARTIAL 与对应风险类别（"文档"/"代码"/"双向"）；
  3. PARTIAL 不阻断 v0.10 release，但需在 release notes "Known issues" 中显式声明。

---

## 7. 验收执行汇总表（Phase 3 已填充 — 详见 `acceptance-execution-report-v0.10.md`）

> Phase 3 执行结果（2026-04-20）：**100 PASS / 13 PARTIAL / 4 SKIP / 0 FAIL / 0 BLOCKED**（共 117 AT）。  
> P0：59 PASS + 7 PARTIAL + 1 SKIP；P1：36 PASS + 5 PARTIAL + 1 SKIP；P2：5 PASS + 1 PARTIAL + 2 SKIP。  
> 自动化基线：`bats skills/codenook-core/tests/*.bats` → **847/847 PASS**。  
> 完整状态矩阵、性能数据、SKIP 原因、SPEC-PATCH 列表均见 `docs/v6/acceptance-execution-report-v0.10.md`。

### 7.1 FR 用例汇总

| AT-ID | 覆盖 FR | 优先级 | 自动化 | 状态 | 备注 |
|-------|---------|-------|--------|------|------|
| AT-INIT-1.1 | FR-INIT-1 | P0 | 需新增 bats | TBD | |
| AT-INIT-1.2 | FR-INIT-1 | P1 | 已有 bats | TBD | |
| AT-INIT-2.1 | FR-INIT-2 | P1 | 需新增 bats | TBD | |
| AT-INSTALL-1.1 | FR-INSTALL-1 | P0 | 已有 bats | TBD | |
| AT-INSTALL-1.2 | FR-INSTALL-1 | P0 | 已有 bats | TBD | |
| AT-INSTALL-1.3 | FR-INSTALL-1 | P1 | 已有 bats | TBD | |
| AT-INSTALL-1.4 | FR-INSTALL-1 | P1 | 需新增 bats | TBD | |
| AT-INSTALL-G01 | FR-PLUGIN-G01 | P0 | 已有 bats | TBD | A1-8 |
| AT-INSTALL-G02 | FR-PLUGIN-G02 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G03 | FR-PLUGIN-G03 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G04 | FR-PLUGIN-G04 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G05 | FR-PLUGIN-G05 | P0 | 已有 bats | TBD | A1-3 |
| AT-INSTALL-G06 | FR-PLUGIN-G06 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G07 | FR-PLUGIN-G07 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G08 | FR-PLUGIN-G08 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G09 | FR-PLUGIN-G09 | P1 | 需新增 bats | TBD | |
| AT-INSTALL-G10 | FR-PLUGIN-G10 | P0 | 已有 bats | TBD | |
| AT-INSTALL-G11 | FR-PLUGIN-G11 | P0 | 已有 bats | TBD | A1-8 |
| AT-INSTALL-G12 | FR-PLUGIN-G12 | P0 | 手动 + 需新增 bats | TBD | |
| AT-MANIFEST-1 | FR-PLUGIN-MANIFEST | P0 | 已有 bats | TBD | A2-10 |
| AT-TASK-1.1 | FR-TASK-1 | P0 | 已有 bats | TBD | |
| AT-TASK-1.2 | FR-TASK-1 | P1 | 已有 bats | TBD | |
| AT-TASK-2.1 | FR-TASK-2 | P0 | 已有 bats | TBD | |
| AT-TASK-2.2 | FR-TASK-2 | P1 | 已有 bats + 手动 | TBD | A2-3 |
| AT-TASK-3.1 | FR-TASK-3 | P0 | 已有 bats | TBD | |
| AT-TASK-3.2 | FR-TASK-3 | P1 | 已有 bats | TBD | A1-2 PARTIAL |
| AT-TASK-4.1 | FR-TASK-4 | P1 | 已有 bats | TBD | A2-2 |
| AT-TICK-1.1 | FR-TICK-1 | P0 | 已有 bats | TBD | |
| AT-TICK-1.2 | FR-TICK-1 | P0 | 已有 bats | TBD | |
| AT-TICK-1.3 | FR-TICK-1 | P0 | 已有 bats | TBD | |
| AT-TICK-1.4 | FR-TICK-1 | P0 | 已有 bats | TBD | |
| AT-TICK-1.5 | FR-TICK-1 | P1 | 已有 bats | TBD | |
| AT-TICK-1.6 | FR-TICK-1 | P1 | 已有 bats | TBD | |
| AT-TICK-2.1 | FR-TICK-2 | P0 | 已有 bats | TBD | |
| AT-TICK-2.2 | FR-TICK-2 | P1 | 已有 bats | TBD | A1-1 PARTIAL |
| AT-TICK-3.1 | FR-TICK-3 | P0 | 已有 bats | TBD | |
| AT-ROUTER-1.1 | FR-ROUTER-1 | P0 | 已有 bats | TBD | |
| AT-ROUTER-1.2 | FR-ROUTER-1 | P1 | 已有 bats | TBD | |
| AT-ROUTER-2.1 | FR-CTX-1/FR-ROUTER-2 | P0 | 已有 bats | TBD | |
| AT-ROUTER-2.2 | FR-CTX-1 | P2 | 已有 bats | TBD | |
| AT-ROUTER-3.1 | FR-ROUTER-3 | P1 | 已有 bats | TBD | |
| AT-ROUTER-4.1 | FR-ROUTER-4 | P0 | 已有 bats | TBD | |
| AT-ROUTER-5.1 | FR-ROUTER-5 | P0 | 已有 bats | TBD | A1-7 PARTIAL / A2-7 |
| AT-CHAIN-1.1 | FR-CHAIN-1 | P0 | 已有 bats | TBD | |
| AT-CHAIN-2.1 | FR-CHAIN-2 | P1 | 已有 bats | TBD | |
| AT-CHAIN-3.1 | FR-CHAIN-3 | P1 | 已有 bats | TBD | |
| AT-CHAIN-4.1 | FR-CHAIN-4 | P2 | 已有 bats | TBD | |
| AT-CHAIN-5.1 | FR-CHAIN-5 | P1 | 已有 bats | TBD | |
| AT-MEM-1.1 | FR-MEM-1 | P0 | 已有 bats | TBD | |
| AT-MEM-1.2 | FR-MEM-1 | P0 | 已有 bats | TBD | |
| AT-MEM-2.1 | FR-MEM-2 | P1 | 已有 bats | TBD | |
| AT-MEM-2.2 | FR-MEM-2 | P1 | 已有 bats | TBD | |
| AT-MEM-3.1 | FR-MEM-3 | P0 | 已有 bats | TBD | |
| AT-MEM-4.1 | FR-MEM-4 | P0 | 已有 bats | TBD | A2-4 |
| AT-EXTRACT-1.1 | FR-EXTRACT-1 | P0 | 已有 bats | TBD | |
| AT-EXTRACT-1.2 | FR-EXTRACT-1 | P0 | 已有 bats | TBD | |
| AT-EXTRACT-2.1 | FR-EXTRACT-2 | P1 | 已有 bats | TBD | |
| AT-EXTRACT-3.1 | FR-EXTRACT-3 | P1 | 已有 bats | TBD | |
| AT-EXTRACT-4.1 | FR-EXTRACT-4 | P0 | 已有 bats | TBD | A2-9 |
| AT-EXTRACT-4.2 | FR-EXTRACT-4 | P2 | 需新增 bats | TBD | A1-4 PARTIAL |
| AT-EXTRACT-5.1 | FR-EXTRACT-5 | P0 | 已有 bats | TBD | A1-5 PARTIAL / A2-6 |
| AT-DIST-1.1 | FR-DIST-1 | P1 | 已有 bats | TBD | A2-8 |
| AT-DIST-1.2 | FR-DIST-1 | P2 | 已有 bats | TBD | |
| AT-SKILL-1.1 | FR-SKILL-1 | P0 | 已有 bats | TBD | |
| AT-SKILL-2.1 | FR-SKILL-2 | P0 | 已有 bats | TBD | A2-1 |
| AT-ROLE-1.1 | FR-ROLE-1 | P1 | 已有 bats | TBD | |
| AT-CONFIG-1.1 | FR-CONFIG-1 | P0 | 已有 bats | TBD | |
| AT-CONFIG-2.1 | FR-CONFIG-2 | P0 | 已有 bats | TBD | A2-5 |
| AT-CONFIG-3.1 | FR-CONFIG-3 | P0 | 已有 bats | TBD | |
| AT-CONFIG-4.1 | FR-CONFIG-4 | P1 | 已有 bats | TBD | |
| AT-CONFIG-5.1 | FR-CONFIG-5 | P1 | 已有 bats | TBD | |
| AT-CONFIG-6.1 | FR-CONFIG-6 | P1 | 已有 bats | TBD | |
| AT-LLM-1.1 | FR-LLM-1 | P0 | 已有 bats | TBD | |
| AT-LLM-2.1 | FR-LLM-2 | P2 | 需新增 bats | TBD | |
| AT-LLM-3.1 | FR-LLM-3 | P2 | 已有 bats | TBD | |
| AT-SEC-1.1 | FR-SEC-1 | P0 | 已有 bats | TBD | A1-5 PARTIAL |
| AT-SEC-2.1 | FR-SEC-2 | P0 | 已有 bats | TBD | |
| AT-SEC-3.1 | FR-SEC-3 | P0 | 已有 bats | TBD | |
| AT-SEC-4.1 | FR-SEC-4 | P1 | 已有 bats | TBD | |
| AT-QUEUE-1.1 | FR-QUEUE-1 | P1 | 已有 bats | TBD | |
| AT-SESS-1.1 | FR-SESS-1 | P1 | 已有 bats | TBD | A1-6 PARTIAL |
| AT-HITL-1.1 | FR-HITL-1 | P1 | 已有 bats | TBD | |

### 7.2 NFR 用例汇总

| AT-ID | 覆盖 NFR | 优先级 | 状态 | 备注 |
|-------|---------|-------|------|------|
| AT-PERF-1..8 | NFR-PERF-1..8 | P0/P1 | TBD | macOS M1 基线 |
| AT-REL-1 | NFR-REL-1 | P0 | TBD | 手动 |
| AT-REL-2..5 | NFR-REL-2..5 | P0/P1 | TBD | 复用 FR 用例 |
| AT-OBS-1..4 | NFR-OBS-1..4 | P0/P1 | TBD | |
| AT-SEC-NFR-1..5 | NFR-SEC-1..5 | P0/P1 | TBD | |
| AT-COMPAT-1..3 | NFR-COMPAT-1..3 | P1/P2 | TBD | Win 不验 |
| AT-EXT-1..3 | NFR-EXT-1..3 | P0 | TBD | |

### 7.3 E2E 用例汇总

| AT-ID | 优先级 | 状态 | 备注 |
|-------|-------|------|------|
| AT-E2E-01 | P0 | TBD | 部分覆盖 m9-e2e |
| AT-E2E-02 | P0 | TBD | 需新增 |
| AT-E2E-03 | P1 | TBD | 需新增 |
| AT-E2E-04 | P0 | TBD | 部分覆盖 m2 |
| AT-E2E-05 | P1 | TBD | 部分覆盖 m9 |


---

## 8. 附录

### 8.1 现有 bats 用例 → AT 映射表

| 现有 bats 文件 | 主要测试名片段 | 映射 AT |
|---------------|--------------|--------|
| `tests/m1-init-help.bats` | --help / --version | AT-INIT-1.2 |
| `tests/m1-preflight.bats` | unknown phase / 6 checks | AT-TASK-1.2, AT-TICK-2.1, AT-TICK-2.2 |
| `tests/m2-install-orchestrator.bats` | 12-gate happy / fail / upgrade | AT-INSTALL-1.1..1.3, AT-E2E-04（部分） |
| `tests/m2-plugin-format.bats` | G01 | AT-INSTALL-G01 |
| `tests/m2-plugin-schema.bats` | G02 | AT-INSTALL-G02 |
| `tests/m2-plugin-id-validate.bats` | G03 | AT-INSTALL-G03 |
| `tests/m2-plugin-version-check.bats` | G04 | AT-INSTALL-G04 |
| `tests/m2-plugin-signature.bats` | G05 | AT-INSTALL-G05 |
| `tests/m2-plugin-deps-check.bats` | G06 | AT-INSTALL-G06 |
| `tests/m2-plugin-subsystem-claim.bats` | G07 | AT-INSTALL-G07 |
| `tests/m2-stage-source-security.bats` | G08 | AT-INSTALL-G08, AT-SEC-2.1 |
| `tests/m2-plugin-shebang-scan.bats` | G10 | AT-INSTALL-G10, AT-SEC-NFR-3 |
| `tests/m2-plugin-path-normalize.bats` | G11 | AT-INSTALL-G11, AT-SEC-NFR-4 |
| `tests/m2-manifest-load.bats` | manifest list/load | AT-MANIFEST-1 |
| `tests/m3-secrets-resolve.bats` | secrets-resolve | AT-SEC-3.1 |
| `tests/m4-orchestrator-tick.bats` | 6 tick scenarios | AT-TICK-1.1..1.6, AT-TASK-1.1 |
| `tests/m4-dispatch-audit.bats` | 8-key + redact | AT-TICK-3.1, AT-OBS-1, AT-OBS-4 |
| `tests/m4-config-resolve.bats` | merge / provenance | AT-CONFIG-1.1, AT-CONFIG-2.1 |
| `tests/m4-config-mutator.bats` | mutator | AT-CONFIG-3.1 |
| `tests/m4-config-validate.bats` | types/ranges | AT-CONFIG-5.1 |
| `tests/m4-task-config-set.bats` | task-config-set | AT-CONFIG-4.1 |
| `tests/m5-model-probe.bats` | catalog miss / fallback | AT-CONFIG-2.1 |
| `tests/m6-queue-runner.bats` | status / drain / corrupt | AT-QUEUE-1.1 |
| `tests/m6-session-resume.bats` | snapshot ≤2KB + compat | AT-SESS-1.1 |
| `tests/m6-hitl-adapter.bats` | blocking + ledger | AT-HITL-1.1 |
| `tests/m8-router-bootstrap.bats` | bootstrap + lock | AT-ROUTER-1.1, AT-ROUTER-1.2 |
| `tests/m8-router-context-scan.bats` | ≤2KB / warnings | AT-ROUTER-2.1, AT-ROUTER-2.2 |
| `tests/m8-router-select.bats` | scoring / fallback | AT-ROUTER-3.1 |
| `tests/m8-router-dispatch-build.bats` | ≤500B / role filter | AT-ROUTER-4.1 |
| `tests/m8-router-agent.bats` | draft / confirm | AT-ROUTER-5.1 |
| `tests/m8-skill-resolve.bats` | 4-tier resolve | AT-SKILL-1.1 |
| `tests/m8-role-index.bats` | role frontmatter | AT-ROLE-1.1 |
| `tests/m8-task-lock.bats` | acquire / stale | AT-TASK-2.1, AT-TASK-2.2 |
| `tests/m8-draft-config.bats` | draft validate | AT-CONFIG-6.1 |
| `tests/m8-plugin-manifest-index.bats` | discover_plugins | AT-MANIFEST-1 |
| `tests/m9-memory-layer.bats` | knowledge/skills/config | AT-MEM-1.1 |
| `tests/m9-memory-index.bats` | cold / warm / invalidate | AT-MEM-2.1, AT-MEM-2.2 |
| `tests/m9-memory-gc.bats` | caps / promoted | AT-MEM-4.1 |
| `tests/m9-extract-audit.bats` | 8-key / append-only | AT-MEM-3.1, AT-OBS-1, AT-OBS-2 |
| `tests/m9-knowledge-extractor.bats` | secret block / cap 3 | AT-EXTRACT-1.1, AT-EXTRACT-1.2 |
| `tests/m9-skill-extractor.bats` | repeat detection | AT-EXTRACT-2.1 |
| `tests/m9-config-extractor.bats` | KEY=VALUE | AT-EXTRACT-3.1 |
| `tests/m9-extractor-batch.bats` | fan-out / idempotent | AT-EXTRACT-4.1 |
| `tests/m9-distiller.bats` | expression / sandbox | AT-DIST-1.1, AT-DIST-1.2 |
| `tests/m9-dispatch-audit-redact.bats` | 9 patterns | AT-EXTRACT-5.1 |
| `tests/m9-secret-scan.bats` | scan / redact | AT-SEC-1.1 |
| `tests/m9-claude-md-linter.bats` | 4 violation classes | AT-SEC-4.1 |
| `tests/m9-llm-mock.bats` | 4-tier mock | AT-LLM-1.1 |
| `tests/m9-token-estimate.bats` | wc-based | AT-LLM-3.1 |
| `tests/m9-plugin-readonly.bats` | readonly violation | AT-SKILL-2.1, AT-MEM-1.2 |
| `tests/m10-task-chain.bats` | parent/root/4 audit | AT-TASK-3.1, AT-TASK-3.2, AT-CHAIN-5.1 |
| `tests/m10-chain-snapshot.bats` | rebuild / generation | AT-CHAIN-1.1 |
| `tests/m10-chain-summarize.bats` | two-pass / budget | AT-CHAIN-2.1 |
| `tests/m10-router-chain-slot.bats` | slot inject | AT-CHAIN-3.1 |
| `tests/m10-parent-suggester.bats` | top-K / threshold / skip | AT-TASK-4.1, AT-CHAIN-4.1 |
| `tests/e2e/m9-e2e.bats` | e2e smoke | AT-E2E-01（部分） |

### 8.2 缺失测试清单（用于 Phase 3 修复阶段）

> 标 `[需新增 bats]` 或 `[手动]` 的 AT 全列在这里；Phase 3 优先 P0。

| AT-ID | 优先级 | 类型 | 描述 | 建议 bats 文件 |
|-------|-------|------|------|---------------|
| AT-INIT-1.1 | P0 | 需新增 bats | init 完整骨架 + 幂等 | `tests/m1-init-skeleton.bats` |
| AT-INIT-2.1 | P1 | 需新增 bats | 仓库根 install.sh 复制 core | `tests/m1-install-repo.bats` |
| AT-INSTALL-1.4 | P1 | 需新增 bats | --dry-run 不 commit | `tests/m2-install-dry-run.bats` |
| AT-INSTALL-G09 | P1 | 需新增 bats | size cap 1MB / 10MB | `tests/m2-plugin-size.bats` |
| AT-INSTALL-G12 | P0 | 手动 + 需新增 bats | atomic-commit 中断 | `tests/m2-atomic-commit.bats` + reviewer |
| AT-EXTRACT-4.2 | P2 | 需新增 bats | 24h 幂等窗口（PARTIAL） | `tests/m9-extractor-idempotent-window.bats` |
| AT-LLM-2.1 | P2 | 需新增 bats | real-mode 缺密钥护栏 | `tests/m9-llm-real-guard.bats` |
| AT-REL-1 | P0 | 手动 | atomic write SIGTERM 中断 | reviewer 手册 |
| AT-TASK-2.2（payload 不可解析分支）| P1 | 手动 | 永不 unlink | reviewer 手册 |
| AT-E2E-01..05 | P0/P1 | 需新增 bats | v0.10 完整链路 | `tests/e2e/v010-*.bats` 五份 |
| AT-COMPAT-1 | P1 | CI matrix | macOS + ubuntu 双跑 | `.github/workflows/bats.yml` 添 matrix |
| AT-COMPAT-3 | P2 | 需新增 bats | jq 缺失诊断 | `tests/m1-init-deps-check.bats` |

合计 **[需新增 bats]：12 项**，**[手动]：3 项**（其中 G12 同时算手动+bats）。

### 8.3 命名 / 路径速查

- 所有 audit jsonl：
  - `.codenook/dispatch.jsonl`（router / tick）
  - `.codenook/extraction-log.jsonl`（memory / extractor / chain / config）
  - `.codenook/distillation-log.jsonl`（distiller）
  - `.codenook/queues/hitl.jsonl`（HITL ledger）
  - `.codenook/history/config-changes.jsonl`（config mutator）
- 所有 lock：
  - `.codenook/router.lock`
  - `.codenook/tasks/<id>/task.lock`
  - 各 atomic write 内嵌 fcntl
- snapshot：
  - `.codenook/memory/.index-snapshot.json`
  - `.codenook/.chain-snapshot.json`

### 8.4 Phase 3 执行建议顺序

1. **P0 已有 bats** —— 直接 `bats -F pretty skills/codenook-core/tests/`，目标 100% PASS；
2. **P0 PARTIAL** —— 单独跑 + 在 §7 备注列引用 §6 编号；
3. **P0 [需新增 bats]** —— 优先编写 G12 / E2E-01 / E2E-04 / INIT-1.1 / REL-1（手动）；
4. **P1 全集** —— 按 §7 顺序滚动；
5. **NFR perf** —— 在 macOS 单机基线收一次，cross-platform CI 收一次；
6. **P2** —— 时间允许时收尾，否则记入 v0.11 backlog。

---

**END OF DOCUMENT**

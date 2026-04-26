# CodeNook Architecture (v0.29.17 / development v0.5.0)

> Deep-dive companion to [`README.md`](../README.md) and
> [`PIPELINE.md`](../PIPELINE.md). Read those first if you have not.

CodeNook is structured as **three layers** that communicate over a
small, well-defined contract: a plugin-agnostic **kernel**, one or
more domain **plugins**, and the per-task / cross-task **workspace
state**. The kernel never knows the names of phases or roles; the
plugin never knows about HITL queues or the state machine. They meet
on three artefacts: the role's `verdict`-stamped output, the
`gate:` field in `phases.yaml`, and `state.json`.

```
┌──────────────── workspace = ~/code/my-project ────────────────┐
│                                                              │
│  CLAUDE.md   ←── bootloader block (managed by claude_md_sync) │
│                                                              │
│  .codenook/                                                  │
│  ├── codenook-core/    [LAYER 1: kernel, plugin-agnostic]    │
│  │     bin/, _lib/cli/, _lib/install/,                       │
│  │     skills/builtin/, schemas/, templates/                 │
│  ├── plugins/<id>/     [LAYER 2: domain knowledge]           │
│  │     plugin.yaml, phases.yaml, hitl-gates.yaml,            │
│  │     roles/, manifest-templates/, knowledge/, skills/      │
│  ├── tasks/<T-NNN>/    [LAYER 3a: per-task state]            │
│  ├── memory/           [LAYER 3b: cross-task state]          │
│  ├── hitl-queue/       [LAYER 3c: pending gates]             │
│  └── extraction-log.jsonl                                    │
└──────────────────────────────────────────────────────────────┘
```

---

## §1. Three-layer model

### 1.1 Kernel — `<ws>/.codenook/codenook-core/`

Plugin-agnostic, version-pinned. Owns the CLI surface, the state
machine, the HITL adapter, the memory extractors, and the install
pipeline. Re-installable in place via `python3 install.py --upgrade`.

```
codenook-core/
├── bin/                          (intentionally empty; shim lives in .codenook/bin/)
├── _lib/
│   ├── cli/                      (codenook CLI package — see §2.1)
│   │   ├── app.py                  ← dispatcher
│   │   ├── cmd_task.py / cmd_tick.py / cmd_decide.py / cmd_hitl.py
│   │   ├── cmd_extract.py / cmd_status.py / cmd_chain.py / cmd_router.py
│   │   ├── _subproc.py / config.py
│   ├── install/                  (Python installer package)
│   │   ├── cli.py / stage_kernel.py / stage_plugins.py / seed_workspace.py
├── skills/builtin/               (kernel-shipped skills — see §2.2)
├── schemas/                      (JSON-Schema for state.json, queue, hitl, …)
└── templates/                    (codenook-bin shim, memory-config.yaml, pre-commit hook)
```

### 1.2 Plugins — `<ws>/.codenook/plugins/<id>/`

Domain knowledge. Three first-party plugins ship in this repo:
**`development`** (v0.2.0, profile-aware 11-phase software-engineering
pipeline), **`writing`** (v0.1.1, long-form authoring), **`generic`**
(v0.1.2, low-priority catch-all). The plugin contract is in §3.

### 1.3 Workspace state — `<ws>/.codenook/{tasks,memory,hitl-queue}/`

Plain-file state. Resumable across CLI restarts and machine moves.
Audit-trail-by-default. Schema is in §4.

---

## §2. The kernel

### 2.1 CLI surface

A thin Python shim at `<ws>/.codenook/bin/codenook(.cmd)` forwards
to `codenook-core/_lib/cli/__main__.py`. Subcommands:

| Command | What it does |
|---------|--------------|
| `codenook task new --title …` | Allocate a new `T-NNN`, write the initial `state.json`. |
| `codenook task set --task T --field F --value V` | Mutate one whitelisted field on `state.json` (atomic, schema-validated). |
| `codenook tick --task T [--json]` | **Advance the state machine one step.** See §2.3. |
| `codenook decide --task T --phase <p|gate> --decision <verb>` | Resolve a HITL gate. `--phase` accepts both phase id and gate id. |
| `codenook hitl <list\|show\|render\|decide>` | Inspect / render / resolve queue entries. `render` produces a self-contained HTML file. |
| `codenook extract --task T --reason <r> [--phase P]` | Manually fire `extractor-batch.sh` (normally automatic after each phase). |
| `codenook status [--task T]` | Per-task or workspace-wide status snapshot. |
| `codenook chain link / show / detach` | Manage parent/child task chains. |
| `codenook router …` | **Deprecated** (see §7); prints a warning. |
| `codenook preflight` | Validate the installation. |

Returns `0` on success, `1` on runtime failure, `2` on usage / missing
entry-question, `3` on already-attached / not-modified states.

### 2.2 Builtin skills (`skills/builtin/`)

Each builtin ships its own `SKILL.md` + entrypoint (`*.sh` or `*.py`)
plus a sibling `_lib/` shared by all of them.

| Skill | Role |
|-------|------|
| `orchestrator-tick` | The state-machine engine (`_tick.py`). The brain behind `codenook tick`. |
| `preflight` | Validates a `.codenook/` install (paths, schemas, permissions). |
| `extractor-batch` | Dispatcher that fans out the three extractors after every phase or context-pressure event. |
| `skill-extractor` | Detects repeated CLI / script patterns and proposes a reusable skill (`memory/skills/<name>/SKILL.md`). |
| `knowledge-extractor` | Pulls declarative findings (decisions, conventions, env notes) into `memory/knowledge/<topic>.md`. |
| `config-extractor` | Captures config decisions into `memory/configs/`. |
| `hitl-adapter` | Materialises gate entries in `hitl-queue/` and accepts decisions (terminal + html channels). |
| `init` / `install-orchestrator` / `plugin-*` / `sec-audit` | The 12-gate plugin install pipeline (`plugin-format`, `plugin-schema`, `plugin-id-validate`, `plugin-version-check`, `plugin-signature`, `plugin-deps-check`, `plugin-subsystem-claim`, `plugin-shebang-scan`, `plugin-path-normalize`, …). |
| `config-resolve` / `config-validate` / `config-mutator` / `task-config-set` | Config layer (resolve overrides, validate against schema, atomic mutate). |
| `model-probe` / `secrets-resolve` | Capability probes and keyring-backed secret injection. |
| `router` / `router-agent` / `router-context-scan` / `router-dispatch-build` | **Deprecated** routing surface — see §7. |

### 2.3 The `codenook tick` state machine

Algorithm (verbatim from `orchestrator-tick/_tick.py`):

```
1. Read state.json (atomic, schema-validated).
2. If status ∈ {done, blocked, cancelled, error}: emit summary, exit.
3. If in_flight_agent is set:
     a. Read tasks/<T>/outputs/<expected_output>.
     b. Parse frontmatter for `verdict` (and `task_type` for clarify).
     c. If supports_iteration and verdict == needs_revision:
          iteration += 1; if < max_iterations, re-dispatch same phase.
          else: status = blocked.
     d. Run post_validate (if defined). On failure: same iteration logic.
     e. If allows_fanout and decomposed=true: seed child tasks, park parent.
     f. Fire extractor-batch.sh --reason after_phase.
     g. If gate is set: write hitl-queue entry, status = waiting, exit.
     h. Else: advance to next phase in profile.
4. If no in_flight_agent: dispatch the current phase.
     a. Resolve role from phases[<phase>].role.
     b. Render manifest from manifest-templates/phase-N-<role>.md
        (substituting {{TASK_CONTEXT}} from state.summary).
     c. Write manifest to tasks/<T>/prompts/, set in_flight_agent.
     d. Emit dispatch envelope on stdout (status: advanced).
5. Persist state.json. Emit ≤500-byte JSON summary.
```

Status values returned in the JSON envelope: `advanced` (work
happened, loop again), `waiting` (HITL gate or external signal
pending), `done` (terminal success), `blocked` (terminal failure or
operator action required), `error` (kernel-internal — should not
happen).

---

## §3. The plugin contract

A plugin is a self-contained directory installed into
`<ws>/.codenook/plugins/<id>/` (read-only after install). The
required files are:

```
plugins/<id>/
├── plugin.yaml              ← identity + routing + packaging contract
├── phases.yaml              ← catalogue + profiles (v0.2.0) OR flat list (v0.1)
├── hitl-gates.yaml          ← gate id → trigger phase → reviewers + description
├── roles/<role>.md          ← bootstrap profile per role
├── manifest-templates/
│   └── phase-N-<role>.md    ← rendered into tasks/<T>/prompts/ at dispatch
├── knowledge/               ← optional declarative knowledge shipped with the plugin
├── skills/                  ← optional executable skills (e.g. test-runner)
├── validators/              ← optional post_validate scripts
├── transitions.yaml         ← legacy (v0.1); v0.2.0 derives transitions from profiles
├── entry-questions.yaml     ← optional questions asked at `task new`
├── config-schema.yaml + config-defaults.yaml
└── CHANGELOG.md / README.md
```

### 3.1 `plugin.yaml`

Carries two complementary contracts:

- **M2 install-pipeline contract** (required, gates G02–G07): `id`,
  `version`, `type`, `entry_points`, `declared_subsystems`,
  `requires.core_version`.
- **Architecture / packaging surface**: `name`, `applies_to`,
  `keywords`, `examples`, `anti_examples`, `supports_dual_mode`,
  `supports_fanout`, `routing.priority`, `available_skills`, …

Loaded by `install-orchestrator` (at install) and `cmd_tick` /
`cmd_decide` (at runtime).

### 3.2 `phases.yaml` (v0.2.0 catalogue + profiles)

```yaml
phases:                                    # catalogue (map keyed by id)
  clarify:
    role: clarifier
    produces: outputs/phase-1-clarifier.md
    gate: requirements_signoff
  implement:
    role: implementer
    produces: outputs/phase-4-implementer.md
    supports_iteration: true
    allows_fanout: true
    dual_mode_compatible: true
    post_validate: validators/post-implement.sh
  ship:
    role: reviewer                         # role files may be reused
    produces: outputs/phase-11-reviewer.md
    gate: ship_signoff
  # …

profiles:                                  # task_type → ordered phase ids
  feature:  {phases: [clarify, design, plan, implement, build, review, submit, test-plan, test, accept, ship]}
  hotfix:   {phases: [clarify, implement, build, review, test-plan, test, ship]}
  # …
```

Phase-entry fields consumed by orchestrator-tick: `role`,
`produces`, `gate`, `supports_iteration`, `allows_fanout`,
`dual_mode_compatible`, `post_validate`. Legacy v0.1 plugins use a
flat `phases: [{id: …, role: …}, …]` list; the kernel still accepts
both shapes.

### 3.3 `hitl-gates.yaml`

```yaml
gates:
  requirements_signoff:
    trigger: clarify
    required_reviewers: [human]
    description: >
      Approve the clarified requirements before downstream work starts.
```

Loaded by `hitl-adapter` (at queue write) and `cmd_decide` (at
gate resolution).

### 3.4 `roles/<role>.md`

The bootstrap profile a sub-agent sees on dispatch. Contains a
self-bootstrap pointer back to the manifest path under
`tasks/<T>/prompts/phase-N-<role>.md`, the role's one-line job, and
its output contract (`frontmatter_required: [verdict, …]`).

### 3.5 `manifest-templates/phase-N-<role>.md`

Per-phase per-role rendering template. Tick substitutes
`{{TASK_CONTEXT}}` from `state.summary` and writes the rendered
manifest to `tasks/<T>/prompts/`. The manifest can override role
behaviour (e.g. the `phase-11-reviewer.md` template sets
`mode: ship` to flip the reviewer role into final-sign-off mode).

---

## §4. The workspace

### 4.1 `tasks/<T-NNN>/`

```
tasks/T-001/
├── state.json              ← canonical state (schema: codenook-core/schemas/task-state.schema.json)
├── prompts/                ← rendered manifests dispatched to sub-agents
│   └── phase-N-<role>.md
├── outputs/                ← sub-agent outputs (verdict-stamped frontmatter)
│   └── phase-N-<role>.md
├── extracted/              ← (legacy; empty in v0.14.0 — see §7 of memory doc)
└── audit/                  ← dispatch.jsonl, history snapshots
```

`state.json` keys (from `task-state.schema.json`):

| Field | Meaning |
|-------|---------|
| `task_id` | `T-NNN`. |
| `plugin` | Selected plugin id. |
| `phase` | Current phase id (or `null` before first dispatch). |
| `task_type` | Profile selector (set by clarifier; null = plugin default). |
| `profile` | Resolved profile name (cached after first dispatch). |
| `iteration` / `max_iterations` | Iteration counter for `supports_iteration` phases. |
| `dual_mode` | `serial` (default) or `parallel`. |
| `status` | `pending \| in_progress \| waiting \| blocked \| done \| cancelled \| error`. |
| `subtasks` / `depends_on` / `decomposed` | Fanout linkage (see §5). |
| `in_flight_agent` | `{agent_id, role, dispatched_at, expected_output}` while a sub-agent is in flight. |
| `history` | Append-only event log used by debug + the deprecated router. |

### 4.2 `memory/`

```
memory/
├── knowledge/<topic>.md       ← declarative
├── skills/<name>/SKILL.md     ← procedural
├── configs/<entry>.md         ← config decisions
├── index.yaml                 ← human-readable inventory (regenerated on every write)
└── .index-snapshot.json       ← machine cache (mtime-keyed; gitignored)
```

`memory/` is the only persistent store after the v0.14.0 deletion of
the `task_specific` route. See [`memory-and-extraction.md`](memory-and-extraction.md)
for the full flow.

### 4.3 `hitl-queue/` and `extraction-log.jsonl`

`hitl-queue/<task>-<gate>.json` is one JSON object per pending gate
with `prompt`, `context_files`, `decision`, `decided_at`,
`decided_by`. Fully consumed by `hitl-adapter`; empty when
`status` ≠ `waiting`.

`extraction-log.jsonl` is the append-only audit of every memory
write/delete: timestamp, task id, phase, extractor, target path,
hash, action (`create` / `patch` / `dedupe-skip` / `secret-block`).

---

## §5. Concurrency model

Three orthogonal mechanisms:

- **Iteration** (`supports_iteration: true`). When a phase's verdict
  is `needs_revision` or `post_validate` exits non-zero, tick
  re-dispatches the same phase, bumping `state.iteration`. Capped
  by `state.max_iterations`. Default cap: 3.
- **Fanout** (`allows_fanout: true`). When a role emits
  `decomposed: true` in frontmatter, tick reads its subtask list and
  seeds children (`tasks/<T-CHILD>/state.json`), parking the parent
  with `status: waiting` until all children land. The planner is
  the canonical fanout source; the implementer can also fanout for
  parallel implementation.
- **Dual-mode** (`dual_mode_compatible: true`). When a task is
  started with `state.dual_mode = parallel`, tick dispatches `N`
  sub-agents in parallel for that phase (default `parallel_n: 3`)
  and consumes the consensus verdict. Used for design (multiple
  perspectives) and implementation (race-to-green).

The three are composable: a planner phase with fanout under a task
in parallel dual-mode produces `N`-fold subtask graphs.

---

## §6. The bootloader (`CLAUDE.md`)

`claude_md_sync.py` injects an idempotent block, fenced by
`<!-- codenook:begin -->` / `<!-- codenook:end -->`, into the
workspace `CLAUDE.md`. Re-running `install.py` rewrites the block
in place; user content outside the markers is never touched.

The block tells the conductor:

- **When to start a task** — only on explicit user trigger
  ("use codenook to …", "open a codenook task", 走 codenook 流程, …).
- **The four-step protocol** — classify → tick → handle HITL →
  loop. See [`PIPELINE.md` §1](../PIPELINE.md).
- **Hard rules** — relay HITL prompts verbatim; never interpret
  phase outputs; never read role files; never pick a plugin /
  profile.
- **Context-pressure protocol** — at the 80 % token watermark,
  call `extractor-batch.sh --reason context-pressure` (≤200 ms
  async dispatch) and decide `/clear` vs `/compact` based on the
  returned envelope.

Every commit on this repo passes `claude_md_linter.py`, which
enforces the bootloader rules against the in-repo
`skills/codenook-core/...CLAUDE.md` reference.

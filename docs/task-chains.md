# Task Chains (v0.14.0 / development v0.2.0)

How phases chain into a complete task lifecycle: the catalogue +
profiles split, the seven shipped profiles, HITL gates between
phases, iteration on failure, fanout into subtasks, dual-mode
parallel agents, and a worked example walking a `feature` task
through all eleven phases.

> Companion to [`PIPELINE.md`](../PIPELINE.md) (the user-facing
> walkthrough) and [`architecture.md`](architecture.md) (the kernel
> deep dive).

---

## §1. Catalogue + profiles

The development plugin's `phases.yaml` has two top-level keys:

| Key | Shape | Purpose |
|-----|-------|---------|
| `phases:` | Map keyed by phase id. | The **catalogue** — each phase defined exactly once with its role, output path, gate, and feature flags. |
| `profiles:` | Map of `task_type → {phases: [phase id, …]}`. | The **chain** — which subset of catalogue phases to walk, in which order, for a given `task_type`. |

**Why both?** The catalogue keeps phase metadata DRY: a phase like
`build` has one definition, even though five profiles include it.
Profiles keep chain-shape DRY: changing the order of a chain (or
adding a new chain shape) does not require touching any phase
definition. The clarifier picks the `task_type`; tick caches the
resolved profile in `state.profile` after the first dispatch and
walks that ordered list.

---

## §2. The seven profiles

| Profile | Length | Phase chain |
|---------|-------:|-------------|
| `feature` | 11 | `clarify → design → plan → implement → build → review → submit → test-plan → test → accept → ship` |
| `refactor` | 9 | `clarify → design → plan → implement → build → review → test-plan → test → ship` |
| `hotfix` | 7 | `clarify → implement → build → review → test-plan → test → ship` |
| `test-only` | 4 | `clarify → test-plan → test → accept` |
| `docs` | 4 | `clarify → implement → review → ship` |
| `design` | 3 | `clarify → design → ship` |
| `review` | 3 | `clarify → review → ship` |

`ship` is the terminal "deliver" phase for every profile (it
reuses the reviewer role with `mode: ship`). `clarify` is the entry
phase for every profile (it picks the `task_type` and seeds the
profile).

What gets skipped tells you what each profile is *for*:

- **`refactor`** skips `submit` and `accept`: a pure-internal
  change goes straight from review to test, no external PR
  ceremony, no user-facing acceptance.
- **`hotfix`** skips `design`, `plan`, `submit`, `accept`: speed
  matters, the gate density is reduced.
- **`test-only`** skips everything between clarify and the test
  trio: no design, no implementation, no ship — purely a
  test-coverage augmentation task.
- **`docs`** runs implement (as the doc-write step), local review,
  and ship — no design / build / test plumbing.
- **`design`** and **`review`** are stand-alone artefact-producing
  profiles (an ADR / a review report respectively).

Default profile when the clarifier cannot decide: **`feature`**.

---

## §3. HITL gates between phases

Every phase **except `implement`** has a HITL gate. Gate
catalogue:

| Phase | Gate id | Description |
|-------|---------|-------------|
| `clarify` | `requirements_signoff` | Approve the spec (goals, AC, task_type, non-goals). |
| `design` | `design_signoff` | Approve the design before any planning or coding. |
| `plan` | `plan_signoff` | Approve the decomposition before the implementer starts. |
| `implement` | *(none)* | Mechanical iteration is cheaper than approval here. |
| `build` | `build_signoff` | Build/lint/smoke green; cached build command still correct. |
| `review` | `local_review_signoff` | Local code-review critique signed off. |
| `submit` | `submit_signoff` | External submission decision + PR/CL link recorded. |
| `test-plan` | `test_plan_signoff` | Test cases / fixtures / pass criteria approved before tests run. |
| `test` | `test_signoff` | Operator spot-check before user acceptance. |
| `accept` | `acceptance` | Final user acceptance — does it solve the problem? |
| `ship` | `ship_signoff` | Final deliver-mode sign-off; closes the task. |

Decision verbs (passed to `codenook decide --decision …`):

- **`approve`** → tick advances to the next phase in the profile.
- **`reject`** → terminal; `status: blocked`.
- **`needs_changes`** → re-dispatches the same phase (subject to
  iteration cap). Equivalent to verdict `needs_revision`.

---

## §4. Iteration

`supports_iteration: true` is set on `implement` and `test`. When
either of these:

- Returns a frontmatter `verdict: needs_revision`, **or**
- Has a `post_validate` script that exits non-zero (e.g. tests
  still red), **or**
- Receives a `decide --decision needs_changes` on its gate (test
  only — implement has no gate),

tick increments `state.iteration` and re-dispatches the **same**
phase with the same role and a fresh manifest render (which
includes the prior output as upstream context, so the role can
self-correct).

When `state.iteration >= state.max_iterations` (default 3), tick
gives up: `status: blocked` with a `message_for_user` indicating
the iteration cap was hit. To retry: bump the cap with
`codenook task set --task T-001 --field max_iterations --value 6`
and re-tick.

---

## §5. Fanout

`allows_fanout: true` is set on `plan` and `implement`. When such
a phase's output frontmatter contains `decomposed: true` and a
`subtasks:` list, tick:

1. Reads the subtask list from the output (each entry must have
   `title`, `summary`, optional `plugin` and `target_dir`).
2. Allocates new `T-NNN` ids and writes
   `tasks/<T-CHILD>/state.json` for each, with
   `depends_on: [<parent>]`.
3. Parks the parent (`status: waiting`, `subtasks: [<children>]`).
4. Each child runs its own profile to completion (recursive — a
   child can fanout further).
5. When all children land in `status: done`, the parent is
   un-parked and tick advances to the next phase in the parent's
   profile.

Fanout is the canonical way to split a large feature into a tree of
smaller features, each with its own gate cadence and memory
extraction.

---

## §6. Dual-mode

`dual_mode_compatible: true` is set on `design` and `implement`.
When the task is started with `state.dual_mode = parallel`, tick
dispatches **`N` parallel sub-agents** for that phase (default
`parallel_n: 3`) instead of one. The role's frontmatter contract
is unchanged; tick reads all `N` outputs and the consensus verdict
becomes the phase verdict.

Use cases:

- **Design.** Three designers exploring three approaches in
  parallel; the consensus verdict picks the winner (with the other
  two outputs preserved as alternatives in `outputs/`).
- **Implement.** Race-to-green parallel implementations against
  the same plan; the first to pass `post_validate` wins, the
  others are discarded but kept under `outputs/.discarded/` for
  audit.

Iteration and fanout both compose with dual-mode: a parallel
implementer can each fanout into their own subtask trees, and each
parallel branch can iterate independently.

---

## §7. Worked example — a `feature` task

User turn: *"use codenook to add a `--tag` filter to the
`xueba list` CLI command."*

### Tick 0 — task creation

Conductor allocates `T-007`. Initial `state.json`:

```json
{ "task_id": "T-007", "plugin": "development", "phase": null,
  "iteration": 0, "max_iterations": 3, "dual_mode": "serial",
  "status": "pending", "task_type": null, "profile": null,
  "title": "add --tag filter to xueba list",
  "summary": "Filter `xueba list` by --tag <name>; …",
  "history": [] }
```

### Tick 1 — `clarify` dispatch

Tick sees `phase: null`, so it picks the **first phase of the
default profile** (clarify). Renders
`prompts/phase-1-clarifier.md` from
`plugins/development/manifest-templates/phase-1-clarifier.md`,
substituting `{{TASK_CONTEXT}}` with `state.summary`. Sets
`in_flight_agent`. Returns `status: advanced`.

### Tick 2 — `clarify` consume + gate

Conductor confirms the sub-agent has written
`outputs/phase-1-clarifier.md`. Tick reads its frontmatter:

```yaml
---
verdict: ok
task_type: feature
---
```

Sets `state.task_type = "feature"`, `state.profile = "feature"` (the
chain is cached for the rest of the task). Fires
`extractor-batch.sh --task-id T-007 --phase clarify --reason after_phase`
(returns immediately; sub-extractors run async). Writes
`hitl-queue/T-007-requirements_signoff.json` and parks the task
(`status: waiting`). Returns `status: waiting`.

### HITL → `decide --phase clarify --decision approve`

Conductor surfaces the gate verbatim. User approves. Conductor calls
`codenook decide --task T-007 --phase clarify --decision approve`.
Tick consumes the queue entry, sets `status: in_progress`, advances
`phase` to `design`.

### Ticks 3–22 — design through ship

The cycle (dispatch → consume + post_validate → extract → gate →
HITL approve → advance) repeats for each of the next ten phases:

| Phase | What happens |
|-------|-------------|
| `design` | Designer drafts an ADR; gate `design_signoff` approves. |
| `plan` | Planner emits subtasks; in this case `decomposed: false` so no fanout. Gate `plan_signoff` approves. |
| `implement` | Implementer writes the code. `post_validate: validators/post-implement.sh` runs; on first try a unit lint fails, `iteration` bumps to 1, re-dispatch, second try passes. **No gate.** |
| `build` | Builder runs `npm run build`; passes. Gate `build_signoff` approves. |
| `review` | Reviewer (mode: review) writes a critique. Gate `local_review_signoff` approves. |
| `submit` | Submitter records PR URL `https://…/pull/123`. Gate `submit_signoff` approves once external LGTM lands. |
| `test-plan` | Test-planner enumerates 4 cases. Gate `test_plan_signoff` approves. |
| `test` | Tester runs the suite via the `test-runner` skill. `post_validate: validators/post-test.sh` confirms all green. Gate `test_signoff` approves. |
| `accept` | Acceptor confirms the change solves the original problem. Gate `acceptance` approves. |
| `ship` | Reviewer (mode: ship) runs the final-sign-off checklist. Gate `ship_signoff` approves. |

### Tick 23 — terminal

After `ship_signoff` is approved, tick sets `phase: ship`,
`status: done`, appends a `terminal` entry to `state.history`, and
returns `status: done` with the final summary. The conductor relays
the message verbatim and exits the loop.

`tasks/T-007/` after completion:

```
T-007/
├── state.json                      (status: done, profile: feature)
├── prompts/                         (11 manifests)
├── outputs/                         (11 verdict-stamped outputs)
├── audit/dispatch.jsonl             (one line per dispatch)
└── extracted/                       (empty in v0.14.0)
```

`memory/` after completion is whatever the three extractors decided
was worth promoting — typically a handful of `knowledge/*.md`
entries (e.g. one ADR digest, one test convention) and possibly one
extracted skill if the tester ran a novel command pattern.
`memory/index.yaml` is regenerated to include them, ready for the
next task to consume.

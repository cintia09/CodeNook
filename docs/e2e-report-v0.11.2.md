# CodeNook v0.11.2 — Real-User E2E Verification

- **Date**: 2026-04-20
- **Workspace**: `/Users/mingdw/Documents/workspace/development`
- **Source repo**: `/Volumes/MacData/MyData/Documents/project/CodeNook` @ `main` (`3258dbc`, tag `v0.11.2`)
- **Tester**: Copilot CLI E2E verification agent + sub-agent (`general-purpose`, model `claude-opus-4.7`) simulating a brand-new human user
- **Goal**: zero-script, real-user perspective verification of the v0.11.2 install + workflow, after prior tests (878 bats, 117 AT, deep-review) failed to catch v4.9.5↔v0.11 marker drift in real workspace use.

---

## Phase 1 — Reset state

Saved forensic copies under `/Volumes/MacData/MyData/Documents/project/CodeNook/.e2e-scratch/pre-state/`:

| Artefact | Origin | Purpose |
|---|---|---|
| `codenook-pre/` | workspace `.codenook/` (v0.11.1 install) | compare layout drift |
| `CLAUDE.md.pre` | workspace `CLAUDE.md` (v4.9.5-flavored) | what the user was actually staring at |
| `CLAUDE.md.bak.preinstall` | from prior installer backup | closest proxy to user's "true" pre-CodeNook CLAUDE.md |

Reset actions performed:
- `cp CLAUDE.md.bak.preinstall CLAUDE.md` (restored "user wrote their own CLAUDE.md" baseline; sha256 `2e5d4128…bfc4c`, 2 244 lines, 115 114 bytes).
- `rm -rf .codenook .claude/skills/codenook* CLAUDE.md.bak.preinstall`.

Remaining workspace contents (clean baseline):
```
.claude/   .gitignore   CLAUDE.md
```

> **Note vs. task brief**: the brief assumed the workspace had pre-existing `src/`, `tests/`, `scratch/`. None of these existed at reset time — the workspace was already a stripped-down testing environment. The simulated task had to create `src/` and `tests/` from scratch.

---

## Phase 2 — Fresh install (positional path)

```
$ cd /Volumes/MacData/MyData/Documents/project/CodeNook
$ git pull --ff-only        # Already up to date.
$ cat VERSION               # 0.11.2
$ bash install.sh /Users/mingdw/Documents/workspace/development
```

Output (verbatim):
```
🤖 CodeNook v0.11.2
  Workspace : /Users/mingdw/Documents/workspace/development
  Plugin    : development (from .../plugins/development)

✓ INSTALLED: plugin development 0.1.0
✓ Plugin 'development' installed into .../.codenook/
✓ CLAUDE.md bootloader block synced (idempotent)
exit 0
```

### 8-point validation

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Exit code 0 | **PASS** | Positional-path UX (DR-002) works. |
| 2 | `state.json` contains `"version": "0.11.2"` | **FAIL** | File only contains `installed_plugins`. No kernel-version field is written. (Possibly intentional but contradicts the brief's expectation and is undocumented either way.) |
| 3 | `.codenook/plugins/development/` populated | **PASS** | Tree present (`prompts/`, `roles/`, `skills/`, `validators/`, `manifest-templates/`, `examples/`, `knowledge/`). |
| 4 | `.codenook/memory/` skeleton with `knowledge/`, `skills/`, `config.yaml`, `history/` | **FAIL** | `.codenook/memory/` did **not** exist after install. It was created lazily during the first orchestrator-tick run. Brief expected eager creation by installer. |
| 5 | CLAUDE.md has `<!-- codenook:begin --> … <!-- codenook:end -->` markers | **PASS** | Lines 2246–2270. |
| 6 | Marker block content is v0.11/v6 router-agent (not v4.9.5 orchestrator) | **PASS** | Block mentions `router-agent`, `orchestrator-tick`, `dispatch_subagent`, `.codenook/`, `plugins/`, `memory/`. **Does NOT contain** `task-board.json`, `acceptor`, `implementer`, `tester` (as primary roles), or `.claude/codenook/`. v0.11.2 marker content is correct — the original v4.9.5 mismatch bug from v0.11.1 is fixed. |
| 7 | Content outside markers byte-identical to user's pre-install CLAUDE.md | **FAIL (cosmetic)** | Stripped file is 2 246 lines vs 2 244 in original — installer appended 2 trailing blank lines outside the marker block. User content is preserved semantically but not byte-identical. |
| 8 | `claude_md_linter --check-claude-md CLAUDE.md` exits 0 | **FAIL** | Linter exits 1 with **204 errors** ("forbidden domain token 'acceptor'/'designer'/'implementer'/…"). All errors come from the user's pre-existing v4.9.5-flavored content **outside** the codenook marker block. The linter scans the entire file and there is no allow-list for "outside-markers user content", and the installer doesn't warn or strip the legacy tokens. |

**Phase 2 summary**: 4 PASS / 4 FAIL.

---

## Phase 3 — Idempotency

```
$ shasum -a 256 CLAUDE.md > hash-1.txt
$ bash install.sh /Users/mingdw/Documents/workspace/development     # second run
$ shasum -a 256 CLAUDE.md > hash-2.txt
$ diff hash-1.txt hash-2.txt → no diff
```

| Check | Result |
|---|---|
| File hash unchanged after re-install | **PASS** (`ae1eafac…ec20a` both runs) |
| Second-install exit code 0 | **FAIL** — exits **3** with `[G03] id 'development' already installed; use --upgrade` and `[G07] subsystem claim 'domain/development' already owned`. The install message says "✓ CLAUDE.md bootloader block synced (idempotent)" only on the *first* run; on the second run the kernel pipeline aborts before the bootloader sync line, surfacing two errors. The user-visible UX is "✗ kernel install exited with rc=3" — looks like a failure even though no harm is done. |

**Phase 3 summary**: 1 PASS / 1 FAIL — surface idempotency is broken (exit code & error log) even though the file system end-state is idempotent.

---

## Phase 4 — Initialization UX

`init.sh --help` (from source repo, since installer does not symlink it into the workspace) honestly states:

> **All non-meta subcommands are stubs in M1 (exit 2: TODO).**

| Subcommand | Status | Doc |
|---|---|---|
| `--version`, `--help`, `--refresh-models` | live | README §Quick Start table marks as ✅ |
| `init.sh` (no args, seed CWD) | stub (exit 2) | README marks as 🚧 v0.12 — directs user to `bash install.sh <ws>` |
| `--install-plugin`, `--uninstall-plugin`, `--scaffold-plugin`, `--pack-plugin`, `--upgrade-core` | stubs | README marks all 🚧 v0.12 |

`PIPELINE.md` line 46 also carries a v0.11.2 status note (DR-003) about init.sh stub status.

**Doc accuracy**: PASS — README.md and PIPELINE.md both honestly disclose the stub status. The actual command a user must run to "initialize" after install is **just `bash install.sh <ws>`**; no separate init step is required, and the docs say so.

**Init-UX gap**: the user is never told the workspace `.codenook/` is "ready to use". The bootloader's "invoke router-agent" instruction is the *only* hint of what to do next — see Phase 5 for how that lands.

---

## Phase 5 — Real-task lifecycle (sub-agent trip report)

The full trip report is reproduced verbatim below (sub-agent return). Saved at `.e2e-scratch/sub-agent-trip-report.md`.

> # CodeNook E2E Trip Report — Fibonacci task as a brand-new user
>
> Workspace: `/Users/mingdw/Documents/workspace/development`
> Source repo (read-only reference): `/Volumes/MacData/MyData/Documents/project/CodeNook`
> Plugin: `development` v0.1.0 (CodeNook v0.11.2)
> Task: implement `src/fib.py` + `tests/test_fib.py`, driven through the 8-phase pipeline.
>
> > Legend: **[DOC]** = a doc-driven user could have figured this out.
> > **[SRC]** = I had to read source/tests because docs alone didn't cover it.
>
> ---
>
> ## 1. Bootloader read (`CLAUDE.md` tail)
>
> The `<!-- codenook:begin -->` block tells the user (verbatim summary):
>
> - The workspace has plugin `development` installed.
> - "At the start of every turn", invoke the **`router-agent`** skill from a Claude Code or Copilot CLI session: *"Use the router-agent skill to ingest this turn against `.codenook/`."*
> - The router-agent reads `.codenook/state.json`, `.codenook/plugins/development/`, `.codenook/memory/`, and `.codenook/tasks/<id>/`, then dispatches the next phase via `dispatch_subagent` and writes back to `.codenook/tasks/` only.
> - Plugin & source files are read-only.
> - For init.sh subcommands and install flow, see project README and `docs/architecture.md`.
>
> **What's missing for a brand-new user:**
> - No actual command (path/binary) is given. The bootloader assumes the host agent (Claude Code / Copilot CLI) has a built-in skill loader that knows how to "invoke router-agent". A bare-shell user has zero idea where router-agent lives. **[SRC]** — I had to grep the source tree to find `skills/codenook-core/skills/builtin/router-agent/spawn.sh`.
> - No example invocation, no `--help`, no "if you are a CLI user, run X".
> - No mention of `orchestrator-tick` even though it is the workhorse.
> - "dispatch_subagent" is referenced as if known but is not defined or linked.
>
> ---
>
> ## 2. Plugin docs read
>
> `README.md` + `phases.yaml` + `transitions.yaml` + `entry-questions.yaml` + `hitl-gates.yaml` together yield:
>
> - **8 phases**: clarify → design → plan → implement → test → accept → validate → ship.
> - Each phase has a `role` and produces `outputs/phase-N-<role>.md` with a YAML frontmatter `verdict: ok | needs_revision | blocked`.
> - **HITL gates**: `design_signoff`, `pre_test_review`, `acceptance` (all human reviewers).
> - **Transitions**: `ok` advances; `needs_revision` self-loops (max_iterations cap); `blocked` pauses.
> - **Entry questions**: clarify requires `dual_mode`; implement requires `dual_mode`, `max_iterations`, `target_dir`. Others empty.
> - `validators/post-implement.sh` and `post-test.sh` are mechanical "did the role write a file with `verdict:` frontmatter" checks.
> - `examples/add-cli-flag/seed.json` is a seed-input shape (input/target_dir/dual_mode/max_iterations/expected_verdicts), not a `state.json`.
>
> **Doc gaps:**
> - No doc tells the user how `state.json` is created or what its required fields are. Schema lives in `skills/codenook-core/schemas/task-state.schema.json`, not shipped into the workspace. **[SRC]**
> - `examples/seed.json` schema is undocumented; the README never references it.
> - `produces:` files use index `phase-1-…`; dispatched markers use phase id `phase-clarify-…`. Two conventions side-by-side. **[SRC]**
>
> ---
>
> ## 3. Start-task UX
>
> **Attempt A** — do what the bootloader literally says: there is **no router-agent binary on PATH** and no symlink in `.codenook/`. Skill ships only inside the source repo. A user who only ran `install.sh` never sees this file. **[SRC]**
>
> **Attempt B** — invoke `spawn.sh` directly:
> ```
> $ /…/router-agent/spawn.sh --task-id T-001 --workspace /…/development --user-turn "Implement Fibonacci…"
> {"action":"prompt","task_id":"T-001","prompt_path":".codenook/tasks/T-001/.router-prompt.md", …}
> exit 0
> ```
> Worked. Created `router-context.md`, empty `draft-config.yaml`, `.router-prompt.md`.
>
> **The catch:** `spawn.sh` is intentionally LLM-less ("`spawn.sh` does not call an LLM"). It only renders a prompt. Without a Claude Code / Copilot CLI host that spawns the subagent and writes back `router-reply.md`, the loop is stuck at turn 1. No documented way for a CLI-only user to drive it forward.
>
> **Attempt C** — bypass the router and seed `state.json` directly. I read `tests/fixtures/m4/state-valid.json` **[SRC]** to learn the shape, hand-wrote `state.json` for `T-100`, and ran `tick.sh`. This worked perfectly (see §4) — but required deep dives a real user won't do.
>
> ---
>
> ## 4. Phase-by-phase walk (T-100)
>
> For each phase: write `outputs/phase-N-<role>.md` with `verdict: ok` frontmatter, run `tick.sh --task T-100 --workspace . --json`, resolve any HITL gate.
>
> | # | Phase     | Command                                                                   | exit  | tick stdout (key)                                            | Bug-notes |
> |---|-----------|---------------------------------------------------------------------------|------:|--------------------------------------------------------------|-----------|
> | 0 | (init)    | `tick.sh` (state.phase=null)                                              | 0     | `advanced "dispatched clarifier"`                            | Dispatch is a stub: writes `phase-clarify-clarifier.dispatched` but no real LLM call. |
> | 1 | clarify   | write `phase-1-clarifier.md`; tick                                        | 0     | `advanced "dispatched designer"`                             | First attempt **failed silently** because `summary:` value contained a colon → YAML parse error → tick said `awaiting clarifier` with zero diagnostic. **E2E-005**. |
> | 2 | design    | write `phase-2-designer.md`; tick → waiting; `hitl-adapter decide approve`; tick | 0/0 | `waiting "hitl:design_signoff"` → `dispatched planner`     | Works. HITL decide is silent on success. |
> | 3 | plan      | write `phase-3-planner.md`; tick                                          | 0     | `dispatched implementer`                                     | OK. |
> | 4 | implement | **wrote `src/fib.py` + `tests/test_fib.py`** myself; write `phase-4-implementer.md`; tick → waiting; approve `pre_test_review`; tick | 0/0 | `waiting "hitl:pre_test_review"` → `dispatched tester` | Orchestrator does NOT verify code was actually written — only that the role's report file has frontmatter. `post-implement.sh` is paper-only. |
> | 5 | test      | ran real `pytest tests/test_fib.py` (3 passed); write `phase-5-tester.md`; tick | 0 | `dispatched acceptor`                                        | Same paper-check problem; verdict taken on faith. |
> | 6 | accept    | write `phase-6-acceptor.md`; tick → waiting; approve `acceptance`; tick   | 0/0   | `waiting "hitl:acceptance"` → `dispatched validator`         | OK. |
> | 7 | validate  | write `phase-7-validator.md`; tick                                        | 0     | `dispatched reviewer`                                        | OK. |
> | 8 | ship      | write `phase-8-reviewer.md`; tick                                         | 0     | `{"status":"done","next_action":"noop"}`                     | Final `phase=complete status=done`. `_pending/T-100.json` written. |
>
> Final pytest:
> ```
> 3 passed in 0.01s
> ```
>
> ---
>
> ## 5. Memory extraction
>
> ```
> .codenook/memory/
> ├── _pending/T-100.json          ← {"task_id":"T-100","queued_at":"…"}
> ├── config.yaml
> ├── history/
> │   ├── extraction-log.jsonl     ← 30+ lines: knowledge/skill/config dispatches
> │   ├── .extractor-knowledge-extractor.err
> │   ├── .extractor-skill-extractor.err
> │   └── .extractor-config-extractor.err
> ├── knowledge/                   ← EMPTY
> └── skills/
> ```
>
> **Found:** `_pending/T-100.json` (distiller marker); `extraction-log.jsonl` (extractors dispatched per phase).
>
> **Missing / suspicious:**
> - `knowledge/` is empty after 8 successful phases.
> - `.extractor-knowledge-extractor.err` is full of `[best-effort] candidate parse failed: Expecting value: line 1 column 2 (char 1)` per phase. The extractor is JSON-parsing role outputs that are Markdown + YAML, so it always fails.
> - `extraction-log.jsonl`: every knowledge `extract_failed`, every skill/config `below_threshold (max_count=0)`. Memory layer is a no-op for this task. **E2E-009**.
>
> Dirs are created lazily by extractors (not by `install.sh`).
>
> ---
>
> ## 6. Dual-mode preflight (DR-007)
>
> Created `T-200` without `dual_mode`:
> ```
> $ tick.sh --task T-200 --workspace . --json
> {"status":"blocked","next_action":"missing: dual_mode",
>  "message_for_user":"Please answer first: dual_mode"}
> EXIT=1
> ```
>
> **Finding:** orchestrator **blocks** with `status=blocked`; does NOT silently default to serial. Good.
>
> **However:** no interactive prompt, no choice menu, no hint of allowed values (`serial`/`parallel` only documented in the schema enum). User has to know they must edit `state.json` or re-engage router. **E2E-006**.
>
> ---
>
> ## 7. Task chains / parent_suggester
>
> `_lib/parent_suggester.py` is **not on `sys.path`** by default:
> ```
> $ python3 -m parent_suggester …
> No module named parent_suggester
> ```
>
> With `PYTHONPATH=…/skills/builtin/_lib` set:
> ```
> $ python3 -m parent_suggester --workspace . --brief "Add iterative fibonacci helper…" --json --threshold 0.05
> [{"task_id":"T-300","title":"Implement Fibonacci memoization helper",
>   "score":0.636364,"reason":"shared: add, fib, fibonacci, helper, memoization"}]
> ```
>
> Algorithm works; surfacing UX does not. No wrapper script. **E2E-007**.
>
> **Schema mismatch (E2E-008):** prompt asked for a `parent` field, but the schema field is `parent_id` (with sibling `chain_root`). I had to grep `task_chain.py` to discover this. Plugin README and bootloader never mention either.
>
> I created `T-CHILD` with `parent_id: T-100, chain_root: T-100` and ran tick. It dispatched `clarifier`, but **the dispatch manifest does not include `parent_id`**:
> ```
> {"execute":"agent","task":"T-CHILD","plugin":"development","phase":"clarify",
>  "role":"clarifier","produces":"outputs/phase-1-clarifier.md"}
> ```
> Subagent has no idea it has a parent — context isn't propagated. Also: T-100 is `done`, so `parent_suggester` correctly skips it (spec §5.2). To prove the suggester worked I needed a *pending* sibling (T-300); for a real user whose only prior task is finished, the suggester returns `[]` and feels broken. **E2E-010**.
>
> ---
>
> ## 8. Findings (sub-agent's E2E-NNN list)
>
> | ID       | Severity | Location | Description | User impact | Suggested fix |
> |----------|----------|----------|-------------|-------------|---------------|
> | **E2E-001** | **CRITICAL** | `CLAUDE.md` bootloader | Tells user to "invoke the router-agent skill" but provides no command/path/example. Skills live in source repo, not workspace. | A new CLI user cannot start a task at all without reading source. | `install.sh` should symlink `router-agent` / `orchestrator-tick` into `.codenook/bin/`, OR bootloader includes the literal command `codenook router --task T-NNN --user-turn "…"`. |
> | **E2E-002** | **HIGH** | router-agent design | `spawn.sh` does not invoke an LLM by design — only renders a prompt. Without a Claude Code / Copilot CLI host that knows to spawn the subagent, the router loop never advances past turn 1. | Plain-shell users and CI scripts cannot use the router at all. | Ship a reference host driver (thin Python loop that pipes `.router-prompt.md` to a configured LLM and writes back `router-reply.md`). |
> | **E2E-003** | **HIGH** | docs / `.codenook/` | `state.json` schema only in `schemas/task-state.schema.json` and example only in `tests/fixtures/m4/state-valid.json`. Neither shipped into workspace. | Users seeding tasks manually must dig through tests. | Copy schema + annotated `state.example.json` into `.codenook/` on install; reference from bootloader. |
> | **E2E-004** | **MEDIUM** | `phases.yaml` + dispatch markers | `produces:` files are `phase-<idx>-<role>.md`; dispatch markers are `phase-<id>-<role>.dispatched`. Two conventions in same dir. | Confusing during debugging — grep for `phase-1` misses `phase-clarify`. | Pick one convention (recommend phase id everywhere). |
> | **E2E-005** | **HIGH** | `_tick.py:read_verdict` | When YAML frontmatter is malformed (e.g. unquoted colon in `summary:`), `read_verdict` → None → `output_ready` False → tick reports `"awaiting <role>"` with no error. | Looks like the system is hung when in fact the file is right there but unparseable. Wasted my first tick. | Distinguish "missing" vs "present-but-unparseable" in tick output; emit YAML error to stderr / `next_action`. |
> | **E2E-006** | **MEDIUM** | entry-questions UX | Missing-field response is one-line `"missing: dual_mode"`, no allowed values, no recovery instructions, exit 1. | Dead-end; user must read schema for legal enum. | Include allowed values in `message_for_user`: `"dual_mode required: serial|parallel — set in state.json or rerun router."` |
> | **E2E-007** | **MEDIUM** | `_lib/parent_suggester.py` | Runs only with manual `PYTHONPATH` set; no shipped wrapper script under `skills/builtin/`. | Documented "parent preflight" UX is invisible to anyone not reading `_lib/`. | Add `skills/builtin/parent-suggest/spawn.sh` mirroring router-agent layout. |
> | **E2E-008** | **MEDIUM** | task-chain field naming | Schema/code use `parent_id` and `chain_root`. Bootloader and plugin README never mention either; CodeNook docs sometimes say `parent`. | Users guessing `parent:` will fail (additionalProperties=false) or be silently lost. | Document `parent_id` + `chain_root` in plugin README; add `task-chain link --child T-X --parent T-Y` helper. |
> | **E2E-009** | **HIGH** | knowledge-extractor | Extractor JSON-parses role-output Markdown and fails on every phase. `.codenook/memory/knowledge/` is empty after a successful 8-phase run. `.err` files silently accumulate. | Advertised "memory layer" produces nothing for normal runs. | Change extractor to consume YAML frontmatter (what roles emit), or document that role outputs must include a JSON candidate block. Surface failures via tick. |
> | **E2E-010** | **LOW** | parent_suggester behavior | Skips `done`/`cancelled` per spec §5.2. For a brand-new user whose first task just finished, suggesting it returns `[]`. | "Why doesn't it suggest the obvious parent?" reaction. | Soften rule (suggest done tasks within last N days), or document the exclusion in router-agent's parent-preflight prompt. |
> | **E2E-011** | **MEDIUM** | post-validate scripts | `post-implement.sh` / `post-test.sh` only check role file exists with `verdict:` line. No check that `target_dir` contains code, no check tests actually ran. | Pipeline can return `done` even if implementer never wrote a single source file. (I wrote `src/fib.py` myself; orchestrator never noticed.) | Make `post-implement.sh` consult role-output frontmatter for `produced_files:` and assert their existence under `target_dir`. Same for tester (`tests_passed: N`). |
> | **E2E-012** | **LOW** | dispatch manifest | Manifest sent to subagent (`{execute,task,plugin,phase,role,produces}`) does not include `parent_id`, `target_dir`, prior phase outputs, or HITL feedback. | Roles see no context, so even with a real LLM host, agent has nothing to work with. | Expand `render_manifest` to include `target_dir`, `parent_id`, prior outputs, last HITL comment. |
> | **E2E-013** | **LOW** | HITL adapter UX | `hitl-adapter terminal.sh decide …` is silent on success. | User can't tell if the decision was accepted vs swallowed. | Print `{"id":"…","decision":"approve"}` on success, even in non-`--json` mode. |
> | **E2E-014** | **LOW** | `.codenook/state.json` | Workspace `state.json` is `{"installed_plugins":[…]}` — different schema from `tasks/<id>/state.json`. Same filename, different shape. | Confusion when grep'ing/debugging. | Rename one (workspace file → `installed.json` or `plugins.json`). |
> | **E2E-015** | **LOW** | extractor logging | Three sibling `.extractor-*-extractor.err` files accumulate "best-effort … parse failed" with no dedup. Grow unbounded. | Disk noise; obscures real failures. | Rotate or de-dup; emit one warning per unique failure. |
>
> ---
>
> ### Net result (sub-agent verbatim)
>
> - The Fibonacci task **was** completed E2E through the orchestrator: 8 phases advanced, 3 HITL gates approved, real pytest passed. State machine is solid.
> - BUT the journey required reading ~10 source files (router-agent SKILL.md, `_tick.py`, schemas, fixtures, `parent_suggester.py`, `task_chain.py`, validators) that no documentation pointed me to.
> - The "user invokes router-agent" story in the bootloader is currently aspirational outside Claude Code / Copilot CLI; the actual fallback (seed `state.json` + drive `tick.sh` manually) is undocumented and uses an internal schema.
> - Memory extraction is plumbed but produces nothing useful in this run; this is the highest-impact silent failure observed.

---

## Phase 6 — Findings (severity-ordered, including main-agent additions E2E-016…019)

The 15 sub-agent findings are reproduced above. Below are 4 additional findings the main verification agent observed in Phases 1–4 that the sub-agent could not see:

### CRITICAL

| ID | Where | What | User impact | Suggested fix |
|---|---|---|---|---|
| **E2E-001** | `CLAUDE.md` bootloader marker | "Invoke the router-agent skill" with no command/path/example. | New CLI user cannot start a task at all. | Symlink `router-agent`/`orchestrator-tick` to `.codenook/bin/` and write the literal command into the bootloader. |

### HIGH

| ID | Where | What | User impact | Suggested fix |
|---|---|---|---|---|
| **E2E-002** | router-agent | `spawn.sh` is intentionally LLM-less — without a Claude Code/Copilot CLI host the loop is stuck at turn 1. | Plain shell / CI cannot use the router. | Ship a reference host driver. |
| **E2E-003** | docs / `.codenook/` | task `state.json` schema/example not shipped to the workspace; user must read `tests/fixtures/m4/`. | Manual seeding is undocumented. | Ship `.codenook/state.example.json` + schema. |
| **E2E-005** | `_tick.py:read_verdict` | Malformed YAML frontmatter is treated as "missing output" with no error. | Hung-state illusion. | Distinguish parse-error vs missing. |
| **E2E-009** | knowledge-extractor | Extractor JSON-parses Markdown role outputs, fails every time; `memory/knowledge/` stays empty after a complete run. | Memory layer (key v0.11 selling point) is silently a no-op. | Switch extractor to YAML-frontmatter consumption or document required JSON block. |
| **E2E-016** | `install.sh` (re-install) | Second run exits **3** with `[G03]/[G07]` errors and `✗ kernel install exited with rc=3`, even though the on-disk result is byte-identical to the first run. Hash idempotent, UX is not. | Looks like a failure; CI scripts / re-provisioning will treat as broken. | Detect "same id, same version, same files" → exit 0 with `↻ already installed (idempotent)` message; require `--upgrade` only for version bump. |
| **E2E-017** | `claude_md_linter` + installer | Linter scans the entire CLAUDE.md and screams 204 errors about user content outside the marker block. Installer doesn't warn the user that pre-existing v4.9.5 tokens in their CLAUDE.md will keep tripping the linter. | `claude_md_linter --check` is unusable on real workspaces with legacy CLAUDE.md content; the user has no idea their file is "lint-broken". | Either (a) restrict linter to `<!-- codenook:begin -->` block by default with `--strict` for whole-file, or (b) have installer emit a warning enumerating forbidden tokens detected outside markers and offer a `--migrate-claude-md` flow. |

### MEDIUM

| ID | Where | What | User impact | Suggested fix |
|---|---|---|---|---|
| **E2E-004** | phase file naming | `phase-<idx>-…` vs `phase-<id>-…` two conventions side-by-side. | Debug confusion. | Pick one. |
| **E2E-006** | entry-questions UX | `missing: dual_mode` with no enum hint, exit 1. | Dead-end. | Include allowed values in `message_for_user`. |
| **E2E-007** | parent_suggester | Requires manual `PYTHONPATH`. | Feature invisible to users. | Ship wrapper. |
| **E2E-008** | task-chain naming | Code uses `parent_id`/`chain_root`; docs sometimes say `parent`. | Manual chain link silently fails. | Document; add helper. |
| **E2E-011** | post-validators | Paper-only; pipeline returns `done` without checking real artefacts. | False-success risk. | Assert `produced_files` exist. |
| **E2E-018** | installer / memory layer | `.codenook/memory/{knowledge,skills,history,_pending}` and `config.yaml` are **not** created by `install.sh`. They appear lazily on first orchestrator-tick. The Phase 2 brief and most docs assume eager creation. | "Where is my memory layer?" right after install. | Have `install.sh` (or `install-orchestrator.sh`) seed an empty memory skeleton with a `.gitkeep` per dir + a default `config.yaml`. |
| **E2E-019** | `state.json` (workspace) | Workspace top-level `state.json` only contains `installed_plugins`; brief & natural reading expect a `version` (kernel) and possibly `plugins.<id>.installed_at`, etc. | Hard to inspect "what version is installed" without grepping the bootloader marker. | Add `kernel_version`, `plugin_versions`, `installed_at` to `state.json`; keep schema versioned. |

### LOW

| ID | Where | What | User impact | Suggested fix |
|---|---|---|---|---|
| **E2E-010** | parent_suggester | Skips done/cancelled — empty result for fresh user. | Feels broken. | Time-window allowance. |
| **E2E-012** | dispatch manifest | No `parent_id`/`target_dir`/prior outputs/HITL feedback. | Roles see no context. | Expand manifest. |
| **E2E-013** | HITL adapter | Silent on success. | Decision-swallowed illusion. | Echo decision. |
| **E2E-014** | `.codenook/state.json` naming | Same filename, two schemas (workspace vs task). | Grep confusion. | Rename workspace file. |
| **E2E-015** | extractor `.err` logs | Unbounded duplicate noise. | Disk + signal loss. | Rotate / de-dup. |

**Severity totals**: CRITICAL 1, HIGH 6, MEDIUM 7, LOW 5 — 19 findings.

---

## Phase 7 — Test-coverage gap analysis

Why didn't 878 bats / 117 AT / deep-review catch any of the above?

1. **No "naive user" persona test.** All bats fixtures start by hand-seeding a known-good `state.json`. None replicate "user reads CLAUDE.md, then tries to run something". E2E-001/002/003 are invisible to fixture-based tests.
2. **No legacy-content coexistence test.** Fixture CLAUDE.md files are either empty or already CodeNook-flavored. Nobody tested "user has a 2 244-line v4.9.5 CLAUDE.md, then we install" — which is the actual upgrade path. E2E-017 / Phase 2 #8 fall into this gap.
3. **Idempotency is asserted at file-hash level only, not exit-code.** Existing tests check that re-running install doesn't change files. None assert exit code 0 on second run. E2E-016 went undetected.
4. **Eager-vs-lazy directory creation is not asserted.** Bats only checks "after a tick, the directory exists", never "right after install, the skeleton exists". E2E-018 invisible.
5. **No memory-layer end-to-end assertion.** `extraction-log.jsonl` is checked for *invocation*, not for *yield*. Every extractor can fail silently with `extract_failed` and tests still pass. E2E-009 invisible.
6. **Validators are tested in isolation with synthetic role outputs that always have a verdict.** No test runs a complete 8-phase loop with the *implementer skipping code generation* to confirm the orchestrator catches it. E2E-011 invisible.
7. **YAML-error path untested.** `read_verdict` is unit-tested for the two valid verdicts and for missing files; no test for malformed frontmatter. E2E-005 invisible.
8. **Schema/doc drift not policed.** `parent_id`/`chain_root` vs `parent` mismatch (E2E-008), `state.json` two-shape collision (E2E-014), `state.json.version` missing (E2E-019) — no consistency test cross-references doc strings vs schema fields.
9. **Help/UX strings not snapshot-tested.** Missing-field error message (E2E-006), HITL silent success (E2E-013), extractor error spam (E2E-015) require golden-output tests that don't exist.

**Recommended new test categories before v0.12:**

- `e2e/naive-user.bats` — purely doc-driven path: install → read bootloader → invoke whatever it tells you → must reach phase 1.
- `e2e/legacy-claude-md.bats` — install over a workspace with v4.9.5/random user CLAUDE.md content; assert linter still passes for marker block, and installer warns about external tokens.
- `e2e/idempotent-exit-code.bats` — re-run install N times; assert exit 0 every time.
- `e2e/memory-yield.bats` — run a full 8-phase task; assert `memory/knowledge/` is non-empty AND `extraction-log.jsonl` contains at least one `extracted` (not `extract_failed`).
- `e2e/post-validator-real-artefact.bats` — implementer phase that produces no code → orchestrator must NOT advance.
- `unit/read-verdict-malformed.bats` — malformed frontmatter must surface a parse error.
- `consistency/schema-vs-docs.bats` — grep that every field name in plugin README/bootloader exists in the JSON schemas.
- `golden/error-messages.bats` — snapshot user-facing error strings for missing fields, idempotent re-install, HITL decisions.

---

## Phase 8 — Recommendation

**Hold v0.11.2 as the current GA tag, but plan an urgent v0.11.3 patch** focused on the CRITICAL + HIGH items (E2E-001, 002, 003, 005, 009, 016, 017). These are all UX/correctness regressions a real user hits in the first 10 minutes; none require a kernel architecture change.

**Then v0.12** should add the test categories enumerated in Phase 7 — without those, the same class of regression will recur.

**Do not ship the "memory layer" as a marketed feature** until E2E-009 is fixed; right now it produces zero output for a normal task, which is worse than not having it at all.

---

*Generated by Copilot CLI E2E verification agent + general-purpose sub-agent (claude-opus-4.7). All shell commands and outputs were executed and captured live; no synthesis without ground truth.*

---

## v0.11.3 follow-up (round 1 — 2026-04-20)

Round-1 fix-pack ships with `v0.11.3`. Commit SHAs are filled in by
the release commit (`git log v0.11.2..v0.11.3`).

| Finding | Severity | Status | Notes |
|---|---|---|---|
| E2E-001 | CRITICAL | **Fixed** | `.codenook/bin/codenook` wrapper + literal commands in CLAUDE.md marker block. |
| E2E-002 | HIGH | **Fixed** | `router-agent/host_driver.py` for plain-shell / CI users. |
| E2E-003 | HIGH | **Fixed** | `.codenook/schemas/` + `state.example.md` shipped by installer. |
| E2E-004 | HIGH | Deferred to v0.12 | Naming consistency sweep planned. |
| E2E-005 | HIGH | **Fixed** | `_tick.read_verdict_detailed` distinguishes missing vs malformed. |
| E2E-006 | MEDIUM | **Fixed** | Entry-questions response carries `allowed_values` + `recovery`. |
| E2E-007 | MEDIUM | Deferred | Covered indirectly by `codenook chain link`. |
| E2E-008 | HIGH | **Fixed** | `parent_id` / `chain_root` documented; `chain link` wrapper. |
| E2E-009 | HIGH | **Fixed** | Extractor consumes role-output YAML frontmatter. |
| E2E-010 | MEDIUM | Deferred | Time-window UX. |
| E2E-011 | MEDIUM | Deferred to v0.12 | Post-validate `produced_files` audit. |
| E2E-012 | MEDIUM | Deferred | Manifest expansion. |
| E2E-013 | MEDIUM | Deferred | HITL silent path. |
| E2E-014 | MEDIUM | Addressed via E2E-019 | Workspace state schema versioning. |
| E2E-015 | LOW | **Fixed** (partial) | Per-extractor `.err` log dedup. |
| E2E-016 | HIGH | **Fixed** | Idempotent re-install exits 0 with no-op message. |
| E2E-017 | HIGH | **Fixed** | `claude_md_linter --marker-only` default; installer warning. |
| E2E-018 | MEDIUM | **Fixed** | `.codenook/memory/` skeleton + `config.yaml`. |
| E2E-019 | MEDIUM | **Fixed** | `state.json` v1 schema (`kernel_version`, `bin`, `files_sha256`). |

**Test deltas:** bats `885 → 895` (`tests/v011_3-fix-pack.bats` adds 10).
New pytest suite `tests/python/` introduces 21 cases. Run all:

```bash
bash skills/codenook-core/tests/run_all.sh
```

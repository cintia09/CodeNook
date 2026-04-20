# Skills Mechanism (v0.14.0)

How CodeNook discovers, dispatches, and persists skills.

A *skill* is a small, named, executable capability — a `SKILL.md`
front-matter manifest plus an entrypoint (shell, Python, or
declarative). The kernel keeps three different stores; this doc
explains where each lives, how it gets loaded, and how the three
relate.

---

## 1. Three skill kinds

| Kind | Lives at | Lifecycle | Examples |
|------|----------|-----------|----------|
| **Builtin** | `<ws>/.codenook/codenook-core/skills/builtin/<name>/` | Shipped with the kernel; copied during `install.py`; immutable in the workspace. | `orchestrator-tick`, `extractor-batch`, `hitl-adapter`, `preflight`, `skill-extractor`, `knowledge-extractor`, `config-extractor`, `init`, `plugin-*` (the 12-gate install pipeline). |
| **Plugin** | `<ws>/.codenook/plugins/<id>/skills/<name>/` | Shipped with a plugin; copied during install; read-only. Listed declaratively in `plugin.yaml` under `available_skills`. | `plugins/development/skills/test-runner/`. |
| **Extracted** | `<ws>/.codenook/memory/skills/<name>/` | Created **at runtime** by `skill-extractor` from observed agent behaviour. Mutable (patched via the same patch-or-create flow). | `memory/skills/run-pytest-with-coverage/`, anything the extractor judged worth promoting. |

A skill is identified by its **name** plus its **tier** (builtin >
plugin > extracted). Resolution is handled by `skill-resolve`
(builtin), which also enforces the tier order so a plugin cannot
shadow a builtin and an extracted skill cannot shadow a plugin one.

---

## 2. Discovery & dispatch by `orchestrator-tick`

When tick advances a phase that requires a skill, the lookup is:

1. **Role-declared.** The role file (`plugins/<id>/roles/<role>.md`)
   declares which skills it may call — e.g. tester references
   `test-runner`. Hard-coded skill names in role files are
   **forbidden**; the role only references logical names that resolve
   through `plugin.yaml.available_skills`.
2. **Resolution.** `skill-resolve --name <n> --plugin <id>` walks
   the three tiers and returns the absolute entrypoint path. Tier
   order: `workspace.builtin` → `workspace.custom` (user drop-ins
   under `plugins/<id>/skills/`) → `plugin_shipped`.
3. **Dispatch.** The entrypoint is invoked as a subprocess with the
   kernel's standard env (`CN_TASK`, `CN_WORKSPACE`,
   `CN_STATE_FILE`, …). Every dispatch is logged to
   `tasks/<T>/audit/dispatch.jsonl`.

Builtin skills (orchestrator-tick, the extractors, hitl-adapter, …)
are not "looked up" — they are imported / shelled out by name from
hard-coded paths inside `_lib/cli/`. The lookup tier model only
matters for **plugin-callable** skills.

---

## 3. Extracted skills — runtime promotion

Plugin and builtin skills are **declarative** — shipped in a release.
Extracted skills are **inductive** — created by `skill-extractor`
when it observes a useful pattern in a phase output.

The pipeline (see `skill-extractor/SKILL.md`):

```
phase output  ──▶  scan for repeated CLI/script invocations (≥3)
                  │
                  ▼
              propose 1 candidate per task
                  │
                  ├── secret-scan      (block on hits, exit non-zero)
                  ├── hash dedupe      (.index-snapshot.json)
                  ├── similarity check (cosine over existing SKILL.md)
                  ├── LLM judge        (worth promoting? merge with X?)
                  ▼
              write or patch  memory/skills/<name>/SKILL.md
                  │
                  ▼
              regenerate     memory/index.yaml
                  │
                  ▼
              append         extraction-log.jsonl
```

Per-task cap: **1 extracted skill per phase**. Failures are
best-effort and exit 0 (audit-logged); secret-blocked failures exit
non-zero so the dispatcher can surface them.

---

## 4. Hash-keyed dedupe + memory_index integration

Both plugin-shipped and extracted skills are hash-keyed for
de-duplication via `_lib/memory_index.py`. The index keeps an
mtime-cached snapshot at
`<ws>/.codenook/memory/.index-snapshot.json` (machine-only,
gitignored) so cold scans of a 1000-skill workspace stay
sub-500 ms and warm scans sub-200 ms.

The human-readable `<ws>/.codenook/memory/index.yaml` is
regenerated on every memory write or delete. It lists each entry
with its tier, name, source task, source phase, hash, and a
one-line digest from frontmatter — this is the file conductors and
role agents read to **inventory** memory without globbing.

---

## 5. Worked example — promoting a skill

Suppose during a `feature` task `T-042` the tester emits an output
that runs `pytest -q --cov=src --cov-report=term-missing` three
times across the phase.

1. Tick consumes `outputs/phase-9-tester.md`, runs `post_validate`,
   and fires
   `extractor-batch.sh --task-id T-042 --phase test --reason after_phase`.
2. The dispatcher fans out the three extractors in parallel.
   `skill-extractor` parses the output for code-fenced shell blocks,
   counts invocations, and proposes a candidate
   `run-pytest-with-coverage`.
3. Pre-write checks: `secret_scan` confirms no leaked tokens; the
   `.index-snapshot.json` shows no exact-hash match; cosine
   similarity against existing `memory/skills/*/SKILL.md` is below
   0.85; the LLM judge confirms it is worth promoting and not a
   duplicate of `test-runner`.
4. The extractor writes:
   ```
   memory/skills/run-pytest-with-coverage/
   ├── SKILL.md         (frontmatter: name, version, source_task, source_phase, hash, tags)
   └── entrypoint.sh    (verbatim shell block)
   ```
5. `memory_index.regenerate()` rewrites
   `memory/index.yaml`, adding:
   ```yaml
   skills:
     - name: run-pytest-with-coverage
       tier: extracted
       source_task: T-042
       source_phase: test
       hash: 3c1f…
       digest: "Run pytest with coverage report on the src tree"
   ```
6. `extraction-log.jsonl` gets one new line:
   `{"ts": "...", "task": "T-042", "phase": "test", "extractor": "skill", "action": "create", "path": "memory/skills/run-pytest-with-coverage/SKILL.md", "hash": "3c1f…"}`.
7. On the next task, the conductor reads `memory/index.yaml` as
   part of the bootloader's standard memory-awareness step. When a
   role declares it may call a `run-pytest-with-coverage`-shaped
   capability, `skill-resolve` finds the extracted skill and
   dispatches it the same way it would a plugin-shipped one.

The same flow applies for **patches**: when the LLM judge says the
candidate is a refinement of an existing skill (similarity ≥ 0.85,
non-trivial diff), `skill-extractor` writes a *patch* — a new
version block appended to the same `SKILL.md` — instead of creating
a new skill. The dedupe hash and the index entry update in place.

---
name: planner
plugin: development
phase: plan
manifest: phase-3-planner.md
output_contract:
  frontmatter_required: [verdict]
  verdict_enum: [ok, needs_revision, blocked]
  extra_verdicts_for_humans: "decomposed/too_complex"
one_line_job: "Decide whether to decompose, and produce the plan + dependency graph."
---

# Planner

**One-line job:** Decide whether to decompose, and produce the plan + dependency graph.

## Self-bootstrap

You were dispatched by `.codenook/codenook-core/skills/builtin/orchestrator-tick`. The
manifest you must follow lives at:

```
.codenook/tasks/<task>/prompts/phase-3-planner.md
```

Read it first; everything you need (criteria, target_dir, prior outputs)
is referenced from there.

## Steps

1. Read clarifier + designer outputs.
2. Decide one of: `not_needed` (single-shot implement), `decomposed` (≥2 subtasks), or `too_complex` (HITL).
3. When decomposed: emit a `subtasks:` array of `{title, summary, depends_on, target_dir}` entries — each independently testable.
4. Write the verdict to the frontmatter; orchestrator-tick.seed_subtasks consumes it via state.subtasks.
5. Cap decomposition fan-out at the workspace `concurrency.max_parallel` ceiling.

## Output contract

Write your full report to `.codenook/tasks/<task>/outputs/phase-3-planner.md`
(the path the orchestrator named via `produces:`). Begin the file with
YAML frontmatter:

```
---
verdict: ok            # or needs_revision / blocked
summary: <≤200 chars>
---
```

Followed by the body. The orchestrator reads only the frontmatter
verdict to decide the next transition; the body is for humans (and the
distiller).

## Knowledge consultation (MANDATORY before answering)

Before drafting your output, you MUST run a memory scan and cite
the results. Skipping the scan means re-inventing patterns the
workspace already knows, and your reviewer cannot tell whether
you checked or guessed. Run, in this order:

1. **Pre-injected baseline.** The phase prompt may pre-inject
   relevant workspace knowledge under the "## 相关 workspace 知识"
   section. Treat those entries as a baseline; do not re-fetch
   them.
2. **Workspace memory — knowledge.** Run
   `<codenook> knowledge search "<query>" --limit 5` for at least
   these queries (skip the obviously-irrelevant ones, but record
   the skip in the Knowledge Consultation Log so the reviewer
   sees the search was real):
   - `planning`, `breakdown`, `architecture`, plus the project / domain nouns from the brief
   Open every hit's `index.md` and note relevance.
3. **Workspace memory — skills.** Run
   `<codenook> discover memory --type skill` (or scan
   `.codenook/memory/skills/<slug>/SKILL.md`) for any
   workspace-shipped playbook that matches your phase. These
   often beat ad-hoc reasoning — invoke one when it fits.
4. **Plugin knowledge.** Walk
   `.codenook/plugins/development/knowledge/` for plugin-shipped
   guidance covering your phase.

Cite every consulted artefact (including zero-hit queries) in a
`## Knowledge Consultation Log` section near the end of your
output. Zero-hit queries proves the search happened — silent
omission reads as "didn't bother".

## Skills

Skills are auto-discovered from the plugin's `skills/` sub-directories. Run

    <codenook> discover plugins --plugin development --type skill --json

to list available skills, then read the chosen `skills/<name>/SKILL.md` for
usage. Invoke a skill via:

    .codenook/codenook-core/skills/builtin/skill-resolve/resolve-skill.sh \
        --name <skill> --plugin development --workspace .

The resolver does the 4-tier lookup (memory > plugin_shipped > workspace_custom
> builtin). Do NOT hard-code skill names in role outputs; treat the
discoverable `skills/` directory as the single source of truth.

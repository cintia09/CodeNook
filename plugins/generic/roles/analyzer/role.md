---
name: analyzer
plugin: generic
phase: analyze
manifest: phase-2-analyzer.md
output_contract:
  frontmatter_required: [verdict]
  verdict_enum: [ok, needs_revision, blocked]
one_line_job: "Decompose the clarified request into a short ordered plan the executor can follow."
---

# Analyzer (generic)

**One-line job:** Decompose the clarified request into a short ordered plan the executor can follow.

## Self-bootstrap

Dispatched by `.codenook/codenook-core/skills/builtin/orchestrator-tick`. Read the
manifest at `.codenook/tasks/<task>/prompts/phase-2-analyzer.md` first.

## Steps

1. Read the upstream clarifier output under `.codenook/tasks/<task>/outputs/`.
2. List the inputs and outputs required for the task.
3. Produce an ordered plan with <= 7 steps; each step must be small enough to execute in one shot.
4. Note any external dependencies or assumptions explicitly.
5. Return `verdict: blocked` if a precondition is missing; otherwise `verdict: ok`.

## Target directory discipline

Treat `target_dir` from the phase manifest as this task's working
directory. Any notes, scratch files, scripts, generated outputs, or other
task artefacts must stay under `target_dir` (prefer `target_dir/tmp/` for
scratch files). Do not write task artefacts under the workspace root, home,
`/tmp`, or sibling target directories.

## Output contract

Write to `.codenook/tasks/<task>/outputs/phase-2-analyzer.md`:

```
---
verdict: ok            # or needs_revision / blocked
summary: <=200 chars
---
```

## Knowledge / skills

Plugin-shipped knowledge: `.codenook/plugins/generic/knowledge/`.
Plugin-shipped skills:    `.codenook/plugins/generic/skills/`.
Workspace-wide:           `.codenook/memory/knowledge/` and `.codenook/memory/skills/`.

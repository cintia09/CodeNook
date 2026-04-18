# Phase-3 dispatch manifest -- executor

> Template rendered by orchestrator-tick into
> `.codenook/tasks/{task_id}/prompts/phase-3-executor.md` before
> dispatching the executor role.

## Header (set by orchestrator)

```
Task:        {task_id}
Plugin:      generic
Phase:       execute                (3 of 4)
Role:        executor
Iteration:   {iteration}
Target dir:  {target_dir}
Prior summary: {prior_summary_path}
Criteria:    {criteria_path}
```

## Your job (one line)

Execute the analyzer plan and produce the artefact.

## Inputs you MUST read

- `.codenook/tasks/{task_id}/state.json` -- task metadata.
- All upstream outputs under `.codenook/tasks/{task_id}/outputs/` for
  phases earlier than execute.
- The criteria document at `{criteria_path}` (if non-empty).
- The plugin role profile at
  `.codenook/plugins/generic/roles/executor.md` -- your operating
  contract; read first.

## Output contract

Write the report to:

```
.codenook/tasks/{task_id}/outputs/phase-3-executor.md
```

Begin with YAML frontmatter:

```
---
verdict: ok                # or needs_revision / blocked
summary: <=200 chars
iteration: {iteration}
---
```

The orchestrator reads ONLY the `verdict` field to compute the next
transition (per `.codenook/plugins/generic/transitions.yaml`).

## Knowledge / skills

- Plugin-shipped knowledge: `.codenook/plugins/generic/knowledge/`.
- Plugin-shipped skills:    `.codenook/plugins/generic/skills/`.
- Workspace-wide:           `.codenook/knowledge/` and
                            `.codenook/skills/` (consume only).

## Iteration cap

`{iteration}` is bumped each time the previous attempt returned
`verdict: needs_revision`. Cap is `state.max_iterations`. Beyond the
cap the orchestrator blocks the task (status=blocked).

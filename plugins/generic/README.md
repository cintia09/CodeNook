# generic plugin

A v6 CodeNook **fallback** plugin that drives arbitrary user requests
through a 4-phase pipeline:
**clarify -> analyze -> execute -> deliver**.

Selected by the M7 router whenever no specialised plugin
(`development`, `writing`, ...) wins on `applies_to` / `keywords`.

## Pinned design

The plugin pins phases `clarify / analyze / execute / deliver` with roles
`clarifier / analyzer / executor / deliverer` as the authoritative spec.

`routing.priority: 10` -- intentionally low; specialised plugins
(`development` ships at priority 50) always win ties.

`applies_to: ["*"]` -- the catch-all wildcard. The router_select shim
(`skills/codenook-core/_lib/router_select.py`, added in M7) treats
`"*"` as the universal fallback and weights it last.

## Layout

```
plugins/generic/
  plugin.yaml            # M2 install manifest + v6 router surface
  config-defaults.yaml   # tier_* model defaults
  config-schema.yaml     # M5 config-validate DSL fragment
  phases.yaml            # 4 phase entries
  transitions.yaml       # ok / needs_revision / blocked table
  entry-questions.yaml   # all phases require nothing
  hitl-gates.yaml        # empty by default
  roles/                 # 4 role profiles
  manifest-templates/    # 4 phase-N-<role>.md dispatch templates
  validators/            # post-execute.sh
  prompts/               # criteria-{execute,deliver}.md
  knowledge/             # conventions.md
  examples/              # seed.json fixtures
```

## Verdict contract

Same as the rest of v6:

```
---
verdict: ok            # or needs_revision / blocked
summary: <=200 chars
---
```

`orchestrator-tick.read_verdict` reads only this; the body is for
humans (and the distiller).

# generic plugin -- changelog

## 0.1.0 -- initial release (M7)

* 4-phase fallback pipeline: clarify -> analyze -> execute -> deliver.
* 4 role profiles in `roles/` (clarifier, analyzer, executor,
  deliverer).
* `applies_to: ["*"]` + `routing.priority: 10` -- the M7 router_select
  shim treats this as the universal fallback.
* `criteria-{execute,deliver}.md` prompts.
* `validators/post-execute.sh` -- post-condition check on executor output.
* `knowledge/conventions.md` plugin-shipped knowledge.
* Manifest exposes both the M2 install-pipeline contract and the v6
  router surface (impl-v6 §M6.2).

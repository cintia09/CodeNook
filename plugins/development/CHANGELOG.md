# development plugin — changelog

## 0.1.0 — initial release (M6, built on v6 plugin framework)

* 8-phase pipeline materialised as `phases.yaml`, `transitions.yaml`,
  `entry-questions.yaml`, `hitl-gates.yaml`.
* 8 role profiles in `roles/` authored against the v6 single-workspace
  model (no `~/.codenook/`, no `templates/` paths).
* Plugin-shipped `test-runner` skill + `post-implement` /
  `post-test` validators.
* `criteria-{implement,test,accept}.md` plugin-shipped acceptance rubrics.
* `pytest-conventions.md` plugin-shipped knowledge.
* Manifest exposes both the M2 install-pipeline contract and the v6
  router surface (impl-v6 §M6.2).

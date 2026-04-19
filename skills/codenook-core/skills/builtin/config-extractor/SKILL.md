name: config-extractor
description: |
  M9.5 builtin extractor. Detects ≥2 distinct KEY=VALUE-shaped config
  signals in a phase log (env vars, port numbers, paths, model names,
  thresholds, explicit `task-config-set k=v`) and proposes config
  entries via the shared patch-or-create flow. Same-key candidates
  default to merge (anti-bloat bias) after one LLM `decide` call.
  Per-task cap = 5. Best-effort: failures audit-log and exit 0;
  secret-blocked exits non-zero.
version: 0.1.0
entrypoint: extract.sh

name: extractor-batch
description: |
  M9.2 dispatcher: fan out knowledge / skill / config extractors after a task
  phase reaches a terminal state, or when the main session reports context
  pressure (≥ 80%).  Idempotent on (task_id, phase, reason); best-effort
  (extractor failures are logged but never propagate).
version: 0.1.0
entrypoint: extractor-batch.sh

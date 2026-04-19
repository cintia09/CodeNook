name: skill-extractor
description: |
  M9.4 builtin extractor. Detects repeated script / CLI invocations
  (≥3 within a phase) and proposes one reusable skill candidate per
  task via the shared patch-or-create flow (secret-scan → hash dedup →
  similarity → LLM judge → write/patch). Per-task cap = 1. Best-effort:
  failures audit-log and exit 0; secret-blocked exits non-zero so the
  dispatcher surfaces the rejection.
version: 0.1.0
entrypoint: extract.sh

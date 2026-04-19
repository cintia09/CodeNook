name: knowledge-extractor
description: |
  M9.3 builtin extractor. Reads task notes, asks the LLM to propose
  reusable knowledge entries, then runs each through the patch-or-create
  decision flow (secret-scan → hash dedup → similarity → LLM judge →
  write). Per-task cap = 3. Best-effort: failures audit-log and exit 0;
  secret-blocked candidates exit non-zero so the dispatcher surfaces
  the rejection.
version: 0.1.0
entrypoint: extract.sh

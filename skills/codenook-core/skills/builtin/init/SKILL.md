# init — Workspace bootstrap

**Role**: Bootstraps a CodeNook workspace skeleton (`.codenook/` dirs,
`memory/{knowledge,skills,history}/`, empty `memory/config.yaml`) so
later milestones can read/write deterministically.

**CLI**:
```bash
init.sh
```

Idempotent: re-running on an existing workspace is a no-op.

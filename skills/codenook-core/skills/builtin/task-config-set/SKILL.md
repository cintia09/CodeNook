# task-config-set — Write Layer-4 override into task state

**Role**: Sets or removes task-level config overrides (Layer-4 in 5-layer chain).

**Exit codes**:
- 0: success
- 1: validation error (key not allowed, task not found)
- 2: usage error

**CLI**:
```bash
set.sh --task <T-NNN> --key <k> --value <v> [--workspace <dir>] [--unset]
```

**Allowed keys**:
- `models.default`
- `models.router`
- `models.planner`
- `models.executor`
- `models.reviewer`
- `models.distiller`
- `hitl.mode`

**Values**:
- Tier symbols: `tier_strong`, `tier_balanced`, `tier_cheap`
- Literal model IDs: any string (warns on unknown but still accepts)

**Behavior**:
- Writes to `tasks/T-NNN/state.json` under `.config_overrides.<key>`
- Idempotent (re-setting same value is no-op)
- `--unset` removes the key

→ Design basis: architecture.md §3.2.4.1 (task-level model override)

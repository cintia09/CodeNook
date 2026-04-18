# plugin-schema — Install gate G02

Validates `<src>/plugin.yaml` against the schema shipped at
`plugin-schema.yaml` next to this skill.

## CLI

```
schema-check.sh --src <dir> [--json]
```

## Required top-level keys

| key | type | notes |
|---|---|---|
| `id` | string | further constrained by gate G03 |
| `version` | string | further constrained by gate G04 |
| `type` | string | one of: `domain`, `tool`, `subsystem` |
| `entry_points` | mapping | non-empty |
| `declared_subsystems` | list of strings | may be empty list |

The schema is intentionally tiny — semantic checks (regex, semver,
collisions) live in dedicated downstream gates.

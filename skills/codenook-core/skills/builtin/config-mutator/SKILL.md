# config-mutator (builtin skill)

## Role

Dispatched config writer. Updates a single config value at workspace
or task scope, validates against schema, and appends a structured
audit-log line. Implements implementation.md §M5.6.

## CLI

```
mutate.sh --plugin <p> --path <dotted.path>
          (--value <new> | --value-json <json>)
          --reason <text> --actor <distiller|user|hitl>
          --workspace <ws>
          [--scope workspace|task --task <tid>]
```

`--scope` defaults to `workspace`. When `--scope task` is given,
`--task` is required.

`--value` parses its argument as JSON for type fidelity (so `5`
round-trips as integer 5, `true` as boolean, `"5"` as the string
`"5"`); it falls back to a raw string when the argument is not
valid JSON (e.g. `some-string`, `tier_balanced`). Use `--value-json`
when you need an unambiguous JSON value and want a hard error on
parse failure.

## Algorithm

1. Validate `--path`: top segment must be in the §45 whitelist; reject
   leading `_` or `..` anywhere.
2. Read current effective value via `config-resolve`. If the new value
   matches → exit 0 with `{"changed": false}` and **do not** touch the
   audit log.
3. For `scope=workspace`: deep-set into
   `<ws>/.codenook/config.yaml.plugins.<p>.overrides.<dotted.path>`.
4. For `scope=task`: deep-set into
   `<ws>/.codenook/tasks/<tid>/state.json.config_overrides.<dotted.path>`.
5. Append one JSON line to `<ws>/.codenook/history/config-changes.jsonl`:

   ```json
   {"ts":"...", "plugin":"...", "scope":"workspace|task",
    "task": "T-NNN" or null, "path":"...", "old": <prev>, "new": <new>,
    "actor":"distiller|user|hitl", "reason":"..."}
   ```

## Invariants

- **#44 router invariant** — if `plugin == __router__` and `path`
  starts with `models.router`, exit 1 (`router model is invariant`).
- **#45 whitelist** — top-level segment of `path` must be in
  `{models, hitl, knowledge, concurrency, skills, memory, router,
  plugins, defaults, secrets}`.
- `actor` enum is enforced; anything else → exit 2.

## Exit codes

- 0 success (changed or noop)
- 1 invariant violation / IO failure
- 2 usage error

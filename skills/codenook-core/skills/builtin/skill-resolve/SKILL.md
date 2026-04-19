# skill-resolve (builtin skill)

## Role

Resolve a skill name against the **4-tier lookup chain** so sub-agents
self-bootstrap deterministically. Implements implementation.md §M5.5.

## Lookup order

1. **plugin_local** — `<ws>/.codenook/memory/<plugin>/skills/<name>/SKILL.md`
2. **plugin_shipped** — `<ws>/.codenook/plugins/<plugin>/skills/<name>/SKILL.md`
3. **workspace_custom** — `<ws>/.codenook/skills/custom/<name>/SKILL.md`
4. **builtin** — `<core_dir>/skills/builtin/<name>/SKILL.md`

Where `<core_dir>` comes from the `CODENOOK_CORE_DIR` environment
variable, falling back to the directory containing `resolve-skill.sh`'s
`skills/builtin` ancestor.

## CLI

```
resolve-skill.sh --name <skill> --plugin <plugin> --workspace <ws> [--json]
```

Output is always JSON (the `--json` flag is accepted for symmetry; default
is JSON anyway).

## Output

Found:
```json
{ "found": true, "name": "...", "path": "...", "tier": "plugin_local" }
```

Not found (exit 1):
```json
{ "found": false, "name": "...", "candidates": [ "...", "...", "...", "..." ] }
```

## Safety

- `--name` is rejected if it contains `/`, `..`, or any character outside
  `[A-Za-z0-9._-]`. Exit code 2 (usage).
- Each candidate path is resolved + a containment check ensures it sits
  under the workspace OR the core directory before being returned.

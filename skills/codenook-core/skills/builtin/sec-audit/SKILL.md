# sec-audit (builtin skill)

## Role

Pre-tick workspace security scanner. Flags:

1. Secrets in workspace files (regex set in `patterns.txt`).
2. Permissions on `.codenook/secrets.yaml` (expected `600`).
3. World-writable files anywhere in `.codenook/`.

Respects `.gitignore` (via `git ls-files --others --ignored`) and always
skips `.git/` + common vendor directories. Never walks outside the
`--workspace` subtree.

## CLI

```
audit.sh --workspace <dir> [--json]
```

## Exit codes

| code | meaning                         |
|------|---------------------------------|
| 0    | no findings                     |
| 1    | at least one finding            |
| 2    | usage / missing workspace       |

## JSON output

```json
{
  "ok": false,
  "findings": [
    { "type": "secret",          "path": "...", "line": 12, "severity": "high" },
    { "type": "permission",      "path": ".codenook/secrets.yaml",
      "severity": "medium", "mode": "644", "expected": "600" },
    { "type": "world-writable",  "path": "...", "severity": "high", "mode": "666" }
  ]
}
```

## M1 scope

Minimal subset of the fuller M2.3 scanner (implementation.md §M2.3).
Currently covers: secret regex, secrets.yaml perms, world-writable under
`.codenook/`. Other M2.3 gates (symlinks, shebang allowlist, keyword
blacklist) land in M2.

# plugin-deps-check — Install gate G06

Verifies the plugin's declared `requires.core_version` constraint
against the running core VERSION.

## CLI

```
deps-check.sh --src <dir> [--core-version <v>] [--json]
```

If `--core-version` is omitted, the core VERSION file shipped with
this repo (`skills/codenook-core/VERSION`) is read.

## Constraint syntax

Comma-separated comparator list (logical AND):

```
>=0.2.0,<1.0.0
>=0.2.0
==0.2.0
```

Supported operators: `>=`, `<=`, `>`, `<`, `==`, `=`, `!=`. Operands
must be valid SemVer 2.0 strings.

# plugin-version-check — Install gate G04

Validates `plugin.yaml.version` is SemVer and (when upgrading)
strictly greater than the installed version.

## CLI

```
version-check.sh --src <dir> [--workspace <dir>] [--upgrade] [--json]
```

## Checks

1. `version` parses as SemVer 2.0 (`MAJOR.MINOR.PATCH[-pre][+build]`).
2. If `--upgrade` and `<workspace>/.codenook/plugins/<id>/plugin.yaml`
   already declares a version, the new version must compare strictly
   greater (precedence rules per semver.org §11).

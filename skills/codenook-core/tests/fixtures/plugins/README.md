# M2 Plugin Install Pipeline — Fixtures

These directories are *static* exemplars of the plugin shapes
exercised by the M2 install pipeline.  Most bats tests build their
fixtures inline (so each test owns its mutation), but having a
named tree on disk:

  - documents what a "real" valid plugin looks like (`good-minimal/`)
  - documents the canonical failure modes for each gate
  - is useful for `install.sh --dry-run` smoke checks during
    manual review and CI.

| fixture | gate it intentionally trips | notes |
|---|---|---|
| `good-minimal/` | none — passes all 12 | `requires.core_version: '>=0.2.0-m2'` |
| `good-with-sig/` | none — adds a valid `plugin.yaml.sig` | `id: good-with-sig` so it can co-exist |
| `bad-no-yaml/` | G01 | no plugin.yaml at root |
| `bad-yaml-missing-id/` | G02 | required field `id` missing |
| `bad-id-uppercase/` | G03 | `id: BadIDUppercase` |
| `bad-version-downgrade/` | (G04 via --upgrade) | declares an old version |
| `bad-deps-too-old/` | G06 | `requires.core_version: '>=99.0.0'` |
| `bad-subsystem-collision/` | G07 | claims `skills/good-minimal-runner` (collides with `good-minimal`) |
| `bad-secret-embedded/` | G08 | leaks a fake `sk-proj-…` key |
| `bad-too-large/` | G09 | 1.5MB `big.bin` (> 1MB per-file limit) |
| `bad-shebang-perl/` | G10 | `#!/usr/bin/perl` |
| `bad-path-traversal/` | G11 | `entry_points.install: ../escape.sh` |
| `bad-symlink-escape/` | G01 | symlink to `/etc/passwd` |

Add a fixture only when the inline form would distract from the
test's intent. Prefer inline mutation otherwise.

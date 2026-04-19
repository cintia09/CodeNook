# CodeNook v0.11.1 — Surface Cleanup Report

> **Release**: v0.11.1 · Surface Cleanup (v5-poc removal)
> **Date**: 2026-04-19
> **Push timestamp (UTC)**: 2026-04-19T22:36:16Z
> **Tag (annotated)**: `v0.11.1` → `311627af7c25db22d5ba4a759c64685414eca82d`
> **Tag (commit ^{})**: `42e635c96c392c2a44db276311766fa41eacd515`
> **Base**: v0.11.0 (`77fe057`) / repo HEAD before this work `4637bfe`
> **Branch**: `main`

---

## 1. Scope

Surface-only cleanup. **Zero functional changes** to codenook-core,
plugins, or installer behaviour. Three classes of residue addressed:

1. The v5 monolithic PoC tree (`skills/codenook-v5-poc/`) — fully
   deleted.
2. Surface markers (banners, version strings, schema examples) still
   advertising the legacy v4.9.5 / v5.0 POC era — bumped to v0.11.0 /
   v6 plugin architecture.
3. Cross-references in plugin docs and v6 design docs that pointed at
   the now-removed v5-poc paths — rephrased or marked as historical.

---

## 2. Pre-removal grep audit

Repo-wide grep before any change (markdown / shell / yaml / python /
json), excluding `skills/codenook-v5-poc/` itself:

```
PIPELINE.md:1                                 # CodeNook Pipeline — Full Workflow (v4.9.5+)
PIPELINE.md:211                               *Generated for CodeNook v4.9.5+*
CHANGELOG.md:482                              ### 🧪 v5.0 POC — Workspace-First Architecture (preview, opt-in)
plugins/development/prompts/criteria-test.md:1     # Test Criteria (v5.0 POC)
plugins/development/prompts/criteria-accept.md:1   # Acceptance Criteria (v5.0 POC)
install.sh:4                                  # CodeNook v4.9.5 (stable) + v5.0 POC Installer
install.sh:7-8                                # Note: v5.0 POC is shipped under skills/codenook-v5-poc/...
docs/implementation.md:155              ### M6 — 第一个真实 plugin：development（从 v5 codenook-v5-poc 提取）
docs/test-plan.md:41                    | 复用 v5-poc reports 中的 e2e 剧本 |
README.md:25                                  v5.0 POC available banner
README.md:298, 483                            "version": "4.9.5"
README.md:599, 626                            v4.9.5 migration prose
docs/README.md:3                           "the shipping product is still v5"
docs/architecture.md:3                  "未实现"
docs/architecture.md:1390+              v5 → v6 migration map
docs/architecture.md:1487               §12 provenance v5-poc reports ref
docs/test-plan.md:699                   H-001 v5-poc reports ref
plugins/development/CHANGELOG.md:3, 8, 13     "ported from v5" entries
plugins/development/README.md:7, 55           "Ported from the v5.0 PoC" / "M6 DoD diff against v5"
skills/codenook-core/README.md:6              "v5 PoC … not a drop-in replacement"
skills/codenook-init/SKILL.md:6               # Agent System Initialization (v4.9.5)
skills/codenook-init/templates/codenook.instructions.md:1   # CodeNook Orchestration Engine (v4.9.5)
```

Source-code grep (`.py` / `.sh` / `.bats`) for `codenook-v5-poc` /
`v5-poc` under `skills/codenook-core/`, `skills/codenook-init/`, and
`plugins/`: **0 hits**. v5-poc is doc-only chatter; safe to delete.

---

## 3. Decision per residue line

| Source | Decision |
|---|---|
| `skills/codenook-v5-poc/` (whole tree) | **DELETE** (commit 1) |
| README banner / nav / schema examples / migration prose | **UPDATE → v0.11.0 / v6** (commit 2) |
| install.sh banner + VERSION fallback + v5-poc note | **UPDATE → v0.11.0** (commit 2) |
| PIPELINE.md header + footer | **UPDATE → v0.11.0+** (commit 2) |
| plugins/development {README, CHANGELOG, criteria-{test,accept}} | **UPDATE → v6 framework** (commit 3) |
| skills/codenook-core/README.md "v5 remains the working reference" | **UPDATE → v5 removed** (commit 3) |
| docs/{README, architecture, implementation, test-plan} | **MARK AS HISTORICAL / COMPLETED** (commit 3) |
| CHANGELOG.md `## [5.0.0-poc.1]` entry | **PRESERVE AS HISTORY** (per task spec §G) |
| skills/codenook-init/* (v4.9.5 banners) | **PRESERVE** — codenook-init is the legacy v4.9.5 stable agent system; its internal version label is intentional and untouched per task scope |

---

## 4. Files deleted

- **Directory removed**: `skills/codenook-v5-poc/`
- **File count**: 79
- **Total size on disk**: 668 KB
- **Total LOC removed**: 11,856 (per `git diff --cached --stat`)

---

## 5. Files updated

### Commit 2 — surface (`850d084`)

- `README.md` — banner, navigation, schema examples (×2), migration section
- `install.sh` — banner (L4), v5-poc note (L7-8), `VERSION` fallback (L10)
- `PIPELINE.md` — header (L1), footer (L211)

### Commit 3 — plugins & docs (`49faf9a`)

- `plugins/development/README.md` — ported→built; M6 DoD note
- `plugins/development/CHANGELOG.md` — 0.1.0 entry rewrite
- `plugins/development/prompts/criteria-test.md` — drop `(v5.0 POC)`
- `plugins/development/prompts/criteria-accept.md` — drop `(v5.0 POC)`
- `skills/codenook-core/README.md` — drop "v5 remains the working reference"
- `docs/README.md` — flip status to implemented
- `docs/architecture.md` — L3 status banner; §9 marked historical
- `docs/implementation.md` — M6 header + 第四部分 marked historical
- `docs/test-plan.md` — L41 row + H-001 case annotated as archive

### Commit 4 — release (`42e635c`)

- `VERSION` — `0.11.0` → `0.11.1`
- `CHANGELOG.md` — `## [0.11.1]` entry prepended

---

## 6. Post-cleanup grep verification

`grep -rn "codenook-v5-poc\|v5-poc" --include="*.md" --include="*.sh"
--include="*.yaml" --include="*.yml" --include="*.py"
--include="*.json"` after all commits:

```
CHANGELOG.md:484                       # in [5.0.0-poc.1] historical entry — preserved per spec §G
CHANGELOG.md:510                       # in [5.0.0-poc.1] historical entry — preserved per spec §G
docs/architecture.md:1387        # in §9 "历史记录 — 已完成" header
docs/architecture.md:1392        # historical migration map (now flagged as completed)
docs/architecture.md:1393        # historical migration map (now flagged as completed)
docs/architecture.md:1402        # historical migration map (now flagged as completed)
docs/architecture.md:1487        # §12 provenance — historical session capture
docs/implementation.md:155       # M6 header — annotated as historical extraction
docs/implementation.md:2321      # 第四部分 migration table — flagged as historical archive
docs/test-plan.md:699            # H-001 — annotated "archive only — 路径已不存在"
```

All remaining hits are inside explicit "historical / completed /
archive" framings. **No live reference points at the deleted tree.**
✅ Clean.

---

## 7. Quality gates

| Gate | Result |
|---|---|
| `bats skills/codenook-core/tests/*.bats` | **851 / 851 PASS** (baseline preserved; matches v0.11.0) |
| Core focused regression (`m1-init-help`, `m1-orchestrator-tick`) | PASS (24 + 23 assertions) |
| `bash -n install.sh` | PASS |
| `install.sh --dry-run` | PASS, banner reads `🤖 CodeNook v0.11.0` |
| `install.sh --install` (HOME-redirected sandbox under `.scratch-v0111/`) | PASS, banner reads `Installed! v0.11.1`, **0 v5-poc artifacts** in installed tree, 26 files placed |
| Source-code import scan for `v5-poc` | **0 hits** under codenook-core / codenook-init / plugins |

---

## 8. Workspace regression

Workspace under inspection: `/Users/mingdw/Documents/workspace/development`

- `.codenook/` layout: `memory/` + `tasks/` (1004 task dirs) — pre-existing v6 workspace
- No `v5-poc` artefacts present in `.codenook/`
- The workspace's existing `CLAUDE.md` is the legacy v5 PoC bootloader
  (created before this cleanup); it is **user-owned content** and is
  not regenerated by either `install.sh` (codenook-init) or
  `skills/codenook-core/init.sh`. Out of scope for this surface
  cleanup; users wishing to migrate that bootloader should re-run
  `init.sh` against the workspace.
- Installer banner verified live (`v0.11.1`); core regression bats
  asserts continue to PASS.

---

## 9. Commits

| # | SHA | Subject |
|---|-----|---------|
| 1 | `969bac7` | refactor(v0.11.1) · remove skills/codenook-v5-poc/ |
| 2 | `850d084` | docs(v0.11.1) · README + install.sh + PIPELINE.md → v0.11.0 |
| 3 | `49faf9a` | docs(v0.11.1) · plugins/development & docs → v6 framework |
| 4 | `42e635c` | chore(release) · v0.11.1 |

All four commits include the `Co-authored-by: Copilot` trailer.

---

## 10. Tag + remote verification

```
$ git ls-remote --tags origin | grep v0.11.1
311627af7c25db22d5ba4a759c64685414eca82d  refs/tags/v0.11.1
42e635c96c392c2a44db276311766fa41eacd515  refs/tags/v0.11.1^{}
```

Push completed: `2026-04-19T22:36:16Z` (`main: 4637bfe..42e635c`,
`new tag v0.11.1`). ✅

---

## 11. BLOCKERs

**None.** Baseline 851 bats PASS preserved across all four commits;
install dry-run and sandboxed install both succeed; remote tag
verified.

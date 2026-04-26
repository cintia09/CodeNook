# CodeNook · Design Docs

Deep-dive companions to the top-level [`README.md`](../README.md) and runtime walkthrough in [`PIPELINE.md`](../PIPELINE.md). Read those first if you have not.

## What's here

| Doc | What's inside |
|-----|---------------|
| [`architecture.md`](architecture.md) | Three-layer deep dive: kernel internals, plugin contract, workspace schema, dispatch envelope, bootloader. |
| [`skills-mechanism.md`](skills-mechanism.md) | How builtin / plugin / memory skills are discovered and dispatched. |
| [`memory-and-extraction.md`](memory-and-extraction.md) | The memory layer (`memory/skills/`, `memory/knowledge/`, history snapshots, retention). Knowledge entries are added manually since v0.29.0 — the auto-extraction pipeline is gone. |
| [`task-chains.md`](task-chains.md) | Catalogue + profiles, parent suggestion, iteration, fanout, dual-mode, worked example through every phase. |
| [`vibe-coding-and-multi-agent.md`](vibe-coding-and-multi-agent.md) | Concept primer: why structured multi-agent work beats free-form vibe-coding. |
| [`codenook-training.html`](codenook-training.html) | Standalone slide deck (open in browser). |

## Reading order for new contributors

1. Top-level [`README.md`](../README.md) — the 3-concept mental model (plugin / phase / agent).
2. [`PIPELINE.md`](../PIPELINE.md) — runtime walkthrough of the development plugin's `feature` profile.
3. [`architecture.md`](architecture.md) — kernel + plugin + workspace contract.
4. [`task-chains.md`](task-chains.md) — how phases, profiles, iteration, and fanout fit together.
5. [`skills-mechanism.md`](skills-mechanism.md) and [`memory-and-extraction.md`](memory-and-extraction.md) — the persistence layer.
6. [`vibe-coding-and-multi-agent.md`](vibe-coding-and-multi-agent.md) — the *why*, if you're convincing a team.

## Sibling references

- [`../CHANGELOG.md`](../CHANGELOG.md) — release-by-release history.
- [`../skills/codenook-core/README.md`](../skills/codenook-core/README.md) — kernel package overview.
- [`../plugins/<id>/README.md`](../plugins) — per-plugin overviews.

> **Note on historical material.** Pre-v0.29 design archives (M1–M11 milestone roadmap, v0.11.x acceptance / requirements / test plans, the deprecated `router-agent` spec) have been removed. The kernel and plugin contracts have stabilised; what shipped is in `architecture.md` and the plugin manifests. Older releases are still recoverable from git history (`git log -- docs/`) if you need them.

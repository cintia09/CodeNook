# Behavioral regression suite

End-to-end tests that drive a real Claude Code agent (`claude -p`)
inside an installed CodeNook workspace and assert that its first
`AskUserQuestion` matches the rules encoded in the rendered
`CLAUDE.md` bootloader.

## Why this exists

`tests/python/test_claude_md_contract.py` proves the **markdown is
correct**. This suite proves a **real LLM follows it**. We need both:
the rendered bootloader can be word-perfect and an agent can still
silently skip a `MUST` rule (we observed this for HITL channel-choice
and for the model ask before they were hardened).

## Cost & gating

Each scenario is a real `claude -p` round-trip — tens of seconds and
roughly $0.20–$0.30 per scenario. **This suite is not run in default
CI** and is **not** wired into `tests/run_all.sh`. Run it manually:

- after touching the bootloader's `Hard rules` block,
- after touching `Pre-creation config ask` or any HITL section,
- when investigating an agent regression report.

## Requirements

- `claude` CLI v2+ on `PATH` (Claude Code).
- A target CodeNook workspace with the kernel installed. Defaults to
  `/Users/mingdw/Documents/nook`; override with `NOOK=/path/to/ws`.
- A funded API account for whichever model `claude` is configured
  with.

## Run

```bash
# Full suite (≈ $1 / 5 min).
bash skills/codenook-core/tests/behavioral/bootloader_behaviour.sh

# Single scenario.
bash skills/codenook-core/tests/behavioral/bootloader_behaviour.sh s4

# Different workspace.
NOOK=/path/to/other/workspace bash .../bootloader_behaviour.sh
```

Per-scenario response JSON is dumped to `$OUT` (default
`/tmp/codenook-bootloader-tests/sN.json`) for post-mortem.

## Scenario index

| ID | Simulates | Expected first action |
|----|-----------|------------------------|
| s1 | Bare task request | Pre-task interview question(s) |
| s2 | Interview already answered in the prompt | Execution mode ask |
| s3 | User said "你自己决定" to interview | Execution mode ask (the exemption must NOT propagate) |
| s4 | Interview done + exec mode = sub-agent | Model ask (the historical regression) |
| s5 | Generic "do the boot ritual" prompt | Reads `memory/index.yaml` (proves §Session-start ritual is followed) |

s1–s4 use `--output-format json` and inspect the agent's first
`AskUserQuestion` (denied in `-p` mode, recorded in
`permission_denials`).

s5 uses `--output-format stream-json --verbose` to inspect the
actual `Read`/`Bash` tool calls, since the boot-ritual files are
auto-allowed and never appear in `permission_denials`.

## Adding a scenario

Add a new `case` arm in `bootloader_behaviour.sh` with a
self-contained prompt that simulates "user has answered up to step
N", and a regex of acceptable header/question text fragments for the
expected next ask. Keep prompts in Chinese or English — match the
audience the bootloader was authored for.

# model-probe (builtin skill)

## Role

Discover available LLM models in the current runtime, classify each into
the three tiers (`strong / balanced / cheap`), and write the resulting
catalog so `config-resolve` can expand `tier_*` symbols. Implements
architecture §3.2.4.2 (Model Discovery & Tiering).

## Triggers

- `init.sh --refresh-models` (manual)
- `init.sh --install-plugin` / `--upgrade-core` (auto on install events)
- Workspace catalog older than `ttl_days` (auto-refresh in M2+)
- Main session "刷新模型" natural-language command (M2+)

## Probe sources (in order)

1. **Runtime API** — Claude Code `list_models()` / Copilot CLI registry.
   *M1: not implemented; falls through to source 2.*
2. **`CODENOOK_AVAILABLE_MODELS`** env var — comma-separated model ids.
3. **Builtin fallback** — minimum viable triple (`opus-4.7,sonnet-4.5,haiku-4.5`).

The runtime label is set to `"env"`, `"builtin-fallback"`, or one of the
runtime names as appropriate.

## CLI

```
probe.sh                                       print catalog JSON to stdout
probe.sh --output <file>                       write catalog JSON to <file>
probe.sh --tier-priority <yaml_file>           override built-in priority
probe.sh --check-ttl <file> --ttl-days <int>   exit 0 if fresh, 1 if stale
```

Any catastrophic probe error (e.g. unreadable `--tier-priority` file) →
stderr starts with `probe failed:` and exits non-zero.

## Tier classification

Each model id is matched against `tier_priority` (user-supplied or
built-in). The model's tier is the first priority bucket containing it.
`resolved_tiers.<tier>` is the first id from `tier_priority[tier]` that is
also in `available`.

Built-in `tier_priority` mirrors implementation-v6.md §3.5.1.2:

```yaml
strong:   [opus-4.7, opus-4.6, sonnet-4.6, gpt-5.4]
balanced: [sonnet-4.6, sonnet-4.5, gpt-5.4, gpt-5.4-mini]
cheap:    [haiku-4.5, gpt-5.4-mini, gpt-4.1, sonnet-4.5]
```

## Output schema

```json
{
  "refreshed_at": "ISO-8601 UTC",
  "ttl_days": 30,
  "runtime": "env | builtin-fallback | claude-code | copilot-cli",
  "available": [
    {"id": "opus-4.7", "tier": "strong", "cost": "high", "provider": "anthropic"}
  ],
  "resolved_tiers": { "strong": "opus-4.7", "balanced": "sonnet-4.6", "cheap": "haiku-4.5" },
  "tier_priority": { "strong": [...], "balanced": [...], "cheap": [...] }
}
```

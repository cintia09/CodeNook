# router-triage (builtin skill)

## Role

The router sub-agent's decision engine. Given a user utterance + the
workspace context, decides among:

| decision | meaning                                                    |
|----------|------------------------------------------------------------|
| `chat`   | small talk / clarifications / "what is X" / no side effects|
| `skill`  | a builtin skill matches (M3 set: list/show/help)           |
| `plugin` | one installed plugin's `intent_patterns:` regex matches    |
| `hitl`   | ambiguous — multiple plugins tie → ask user before any side effect |

## Decision algorithm (priority order)

1. **Builtin intent table** (hardcoded for M3):
   * `list-plugins` ← `\b(list|show)\b.*\bplugins?\b`
   * `show-config`  ← `\b(show|print)\b.*\b(config|settings)\b`
   * `help`         ← `\bhelp\b` (whole word, optional surrounding text)
2. **Plugin intent_patterns** — the `intent_patterns:` list in each
   `<ws>/.codenook/plugins/<id>/plugin.yaml` is compiled and tested
   against the user input (`re.search`, case-insensitive). If exactly
   one plugin matches → `decision=plugin`; if ≥2 → `decision=hitl`.
3. **Fall-through**: `decision=chat` with confidence ≤ 0.5.

For `decision=plugin` the skill calls
`router-dispatch-build` to produce the bounded dispatch payload that
gets surfaced as `dispatch_payload` in the output.

## CLI

```
triage.sh --user-input "<text>" [--workspace <dir>] [--task <T-NNN>] [--json]
```

## Exit codes

| code | meaning              |
|------|----------------------|
| 0    | decision rendered    |
| 2    | usage error          |

(Triage never fails closed — even if no plugin matches, `chat` is
always a valid outcome. Dispatch payload assembly errors degrade
gracefully to `dispatch_payload: null` with a warning in `reasons`.)

## Output

```json
{
  "decision":         "plugin",
  "target":           "writing-stub" | null,
  "confidence":       0.85,
  "reasons":          ["matched intent regex '新建小说.*'"],
  "dispatch_payload": "{\"role\":\"plugin-worker\",...}"  // null for chat/hitl
}
```

# plugin-signature — Install gate G05

Optional detached-signature check.  Real cryptographic signing
(GPG / minisign) is deferred to M5; M2 ships the *hook* with a
self-contained sha256 baseline so the orchestrator and packaging
tool can pin authenticity intent today.

## CLI

```
signature-check.sh --src <dir> [--json]
```

## Behaviour

| `plugin.yaml.sig` | `CODENOOK_REQUIRE_SIG` | result |
|---|---|---|
| missing | unset / `0` | pass (signatures are opt-in) |
| missing | `1` | fail (G05) |
| present | any | digest must equal `sha256(plugin.yaml)` |

The signature file may contain leading/trailing whitespace; only the
first non-blank token is consumed.

#!/usr/bin/env bash
# CodeNook v5.0 — Cross-platform keyring helper
# Wraps the Python `keyring` package, which uses the OS-native secret
# store on each platform:
#   * macOS  -> Keychain          (built-in, no extra deps)
#   * Windows -> Credential Locker (built-in, no extra deps)
#   * Linux  -> SecretService / KWallet (libsecret-1; usually pre-installed)
#
# Codenook stores all credentials under the service name "codenook".
# Workspace files reference them as ${keyring:codenook/<key>}.
#
# Usage:
#   keyring-helper.sh check              # verify keyring is usable
#   keyring-helper.sh set    <key>       # prompts (hidden) for value
#   keyring-helper.sh get    <key>       # prints to stdout
#   keyring-helper.sh delete <key>
#   keyring-helper.sh resolve <file>     # expand ${keyring:codenook/X} refs
#
# Exit codes:
#   0 ok | 2 usage error | 3 missing dep | 4 keyring backend failure
set -uo pipefail

SERVICE="codenook"

_re_safe_key='^[A-Za-z0-9_./@-]+$'
_assert_safe_key() {
  [[ "$1" =~ $_re_safe_key ]] || { echo "error: unsafe key '$1'" >&2; exit 2; }
}

_have_python() {
  command -v python3 >/dev/null 2>&1 || {
    echo "error: python3 not on PATH (Windows: install Python 3 and add to PATH, or use 'py -3')" >&2
    exit 3
  }
}

_have_keyring() {
  python3 -c "import keyring" 2>/dev/null || {
    echo "error: 'keyring' Python package missing." >&2
    echo "install: pip install --user keyring" >&2
    exit 3
  }
}

cmd_check() {
  _have_python
  _have_keyring
  # Probe backend.
  python3 - <<PY 2>&1 || { echo "error: keyring backend probe failed" >&2; exit 4; }
import keyring
kr = keyring.get_keyring()
print(f"backend: {kr.__class__.__module__}.{kr.__class__.__name__}")
PY
  echo "✅ keyring usable."
}

cmd_set() {
  local key="${1:-}"; [[ -z "$key" ]] && { echo "usage: set <key>" >&2; exit 2; }
  _assert_safe_key "$key"
  _have_python; _have_keyring
  printf "Value for %s/%s (input hidden): " "$SERVICE" "$key" >&2
  local val; IFS= read -rs val; echo "" >&2
  [[ -z "$val" ]] && { echo "error: empty value rejected" >&2; exit 2; }
  python3 - "$SERVICE" "$key" "$val" <<'PY' || exit 4
import sys, keyring
keyring.set_password(sys.argv[1], sys.argv[2], sys.argv[3])
PY
  echo "stored ${SERVICE}/${key}"
}

cmd_get() {
  local key="${1:-}"; [[ -z "$key" ]] && { echo "usage: get <key>" >&2; exit 2; }
  _assert_safe_key "$key"
  _have_python; _have_keyring
  python3 - "$SERVICE" "$key" <<'PY'
import sys, keyring
v = keyring.get_password(sys.argv[1], sys.argv[2])
if v is None: sys.exit(4)
print(v)
PY
}

cmd_delete() {
  local key="${1:-}"; [[ -z "$key" ]] && { echo "usage: delete <key>" >&2; exit 2; }
  _assert_safe_key "$key"
  _have_python; _have_keyring
  python3 - "$SERVICE" "$key" <<'PY' || exit 4
import sys, keyring
keyring.delete_password(sys.argv[1], sys.argv[2])
PY
  echo "deleted ${SERVICE}/${key}"
}

cmd_resolve() {
  local f="${1:-}"; [[ -z "$f" ]] && { echo "usage: resolve <file>" >&2; exit 2; }
  [[ -f "$f" ]] || { echo "error: $f not found" >&2; exit 2; }
  _have_python; _have_keyring
  python3 - "$SERVICE" "$f" <<'PY'
import sys, re, keyring
service, path = sys.argv[1], sys.argv[2]
pat = re.compile(r"\$\{keyring:" + re.escape(service) + r"/([A-Za-z0-9_./@-]+)\}")
def sub(m):
    v = keyring.get_password(service, m.group(1))
    return v if v is not None else m.group(0)
sys.stdout.write(pat.sub(sub, open(path).read()))
PY
}

case "${1:-}" in
  check)   shift; cmd_check    "$@" ;;
  set)     shift; cmd_set      "$@" ;;
  get)     shift; cmd_get      "$@" ;;
  delete)  shift; cmd_delete   "$@" ;;
  resolve) shift; cmd_resolve  "$@" ;;
  -h|--help|"") sed -n '2,22p' "$0" ;;
  *) echo "unknown command: $1" >&2; exit 2 ;;
esac

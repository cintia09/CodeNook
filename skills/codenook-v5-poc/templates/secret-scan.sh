#!/usr/bin/env bash
# CodeNook v5.0 — Secret scanner
# Scans the workspace and project files for likely-leaked credentials.
# Designed to be invoked by the security-auditor sub-agent at session
# start, or directly from preflight.sh / pre-commit hooks.
#
# Usage:
#   bash secret-scan.sh                # scan default paths, warn-only
#   bash secret-scan.sh --strict       # exit 2 on any finding
#   bash secret-scan.sh --json         # machine-readable output
#
# Exit codes:
#   0 = no findings
#   1 = findings (warn mode)
#   2 = findings (strict mode) OR scanner failure
set -uo pipefail

STRICT=0
JSON=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    --json)   JSON=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  esac
done

WS=".codenook"
IGNORE_FILE="$WS/.secretignore"

# Patterns: name | regex
PATTERNS=(
  "openai|sk-[A-Za-z0-9]{20,}"
  "anthropic|sk-ant-[A-Za-z0-9_-]{20,}"
  "github_pat|ghp_[A-Za-z0-9]{20,}"
  "github_oauth|gho_[A-Za-z0-9]{20,}"
  "github_server|ghs_[A-Za-z0-9]{20,}"
  "github_user|ghu_[A-Za-z0-9]{20,}"
  "github_refresh|ghr_[A-Za-z0-9]{20,}"
  "gitlab_pat|glpat-[A-Za-z0-9_-]{20,}"
  "aws_akid|AKIA[0-9A-Z]{16}"
  "aws_secret|aws_secret_access_key[\"'[:space:]]*[:=][\"'[:space:]]*[A-Za-z0-9/+]{40}"
  "google_api|AIza[0-9A-Za-z_-]{35}"
  "slack_bot|xoxb-[0-9]+-[0-9]+-[A-Za-z0-9]+"
  "slack_user|xoxp-[0-9]+-[0-9]+-[0-9]+-[a-f0-9]+"
  "private_key|-----BEGIN (RSA|OPENSSH|DSA|EC|PGP) PRIVATE KEY-----"
  "internal_ip|(^|[^0-9])(192\.168|10\.|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+"
  "generic_password|(password|passwd|pwd)[\"'[:space:]]*[:=][\"'[:space:]]*['\"][^'\"$\{][^'\"]{6,}['\"]"
)

# Scan targets: workspace + common project config files. Skip binaries
# and the workspace's own history directory (audit logs may quote
# patterns intentionally).
SCAN_PATHS=()
[[ -d "$WS" ]] && SCAN_PATHS+=("$WS")
for f in .env .env.local .env.production config.yaml config.yml \
         settings.json secrets.json package.json composer.json; do
  [[ -f "$f" ]] && SCAN_PATHS+=("$f")
done

# Optional ignore (one glob per line, '#' comments).
IGN_ARGS=()
if [[ -f "$IGNORE_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line## }"; line="${line%% }"
    [[ -z "$line" ]] && continue
    IGN_ARGS+=(--exclude="$line")
  done < "$IGNORE_FILE"
fi

# Run scan: gather findings as <name> <file>:<line>:<excerpt>
FINDINGS=()
for entry in "${PATTERNS[@]}"; do
  name="${entry%%|*}"
  rx="${entry#*|}"
  for tgt in "${SCAN_PATHS[@]}"; do
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      # Skip the scanner itself, the secretignore file, distillation logs
      # (they record patterns), and the security history.
      case "$hit" in
        *secret-scan.sh*|*.secretignore*|*history/security/*|*history/distillation-log.md*) continue ;;
      esac
      FINDINGS+=("$name|$hit")
    done < <(grep -EnIr \
                "${IGN_ARGS[@]+"${IGN_ARGS[@]}"}" \
                --exclude-dir=node_modules --exclude-dir=.git \
                --exclude-dir=.venv --exclude-dir=__pycache__ \
                "$rx" "$tgt" 2>/dev/null || true)
  done
done

count=${#FINDINGS[@]}

if [[ $JSON -eq 1 ]]; then
  printf '{\n  "count": %d,\n  "strict": %s,\n  "findings": [' \
    "$count" "$([[ $STRICT -eq 1 ]] && echo true || echo false)"
  first=1
  for f in "${FINDINGS[@]+"${FINDINGS[@]}"}"; do
    name="${f%%|*}"; rest="${f#*|}"
    file="${rest%%:*}"; rest2="${rest#*:}"
    line="${rest2%%:*}"; excerpt="${rest2#*:}"
    excerpt="${excerpt//\\/\\\\}"; excerpt="${excerpt//\"/\\\"}"
    [[ $first -eq 1 ]] && first=0 || printf ','
    printf '\n    {"pattern":"%s","file":"%s","line":"%s"}' "$name" "$file" "$line"
  done
  printf '\n  ]\n}\n'
else
  if [[ $count -eq 0 ]]; then
    echo "✅ Secret scan: no findings across ${#SCAN_PATHS[@]} target(s)."
  else
    echo "⚠️  Secret scan: $count finding(s):"
    for f in "${FINDINGS[@]}"; do
      name="${f%%|*}"; rest="${f#*|}"
      echo "  [$name] $rest"
    done
    echo ""
    echo "If a finding is a false positive, add the file glob to $IGNORE_FILE."
    echo "If real, rotate the secret and replace the value with a keyring"
    echo "reference: \${keyring:codenook/<name>}"
  fi
fi

if [[ $count -eq 0 ]]; then exit 0; fi
[[ $STRICT -eq 1 ]] && exit 2 || exit 1

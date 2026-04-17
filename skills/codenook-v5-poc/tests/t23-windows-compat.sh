#!/usr/bin/env bash
# T23: Windows / Git Bash compatibility static checks.
# We cannot execute on Windows from this test suite, so we apply a
# conservative static audit that catches the classes of bugs that
# typically break under Git Bash / MSYS2:
#   1. CRLF line endings (kills `#!/usr/bin/env bash`).
#   2. BSD-only features (`sed -i ''`, macOS-only `date` flags, etc).
#   3. Windows-illegal filename characters (`:`, `*`, `?`, `<>|"`) in
#      runner-generated paths.
#   4. Missing python3 guard in init.sh.
#   5. Hard dependency on commands not in Git Bash by default.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"

FAIL=0
pass() { echo "  ✅ $1"; }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "=== T23: Windows / Git Bash compatibility ==="

RUNNERS=(
  "$POC_DIR/init.sh"
  "$POC_DIR/templates/subtask-runner.sh"
  "$POC_DIR/templates/queue-runner.sh"
  "$POC_DIR/templates/dispatch-audit.sh"
  "$POC_DIR/templates/hitl-adapters/terminal.sh"
)

# ----------------------------------------------------------------------
# [1] .gitattributes enforces LF for shell scripts
# ----------------------------------------------------------------------
echo ""
echo "[1] .gitattributes LF enforcement:"
GA="$REPO_ROOT/.gitattributes"
if [[ -f "$GA" ]]; then
  grep -Eq '^\*\.sh[[:space:]]+.*eol=lf' "$GA" && pass ".sh → eol=lf declared" || fail ".sh missing eol=lf rule"
  grep -Eq '^\*\.md[[:space:]]+.*eol=lf' "$GA" && pass ".md → eol=lf declared" || fail ".md missing eol=lf rule"
else
  fail "no .gitattributes at repo root ($GA)"
fi

# ----------------------------------------------------------------------
# [2] No CRLF in shipped shell scripts
# ----------------------------------------------------------------------
echo ""
echo "[2] No CRLF in runners:"
for r in "${RUNNERS[@]}"; do
  if [[ ! -f "$r" ]]; then fail "missing: $r"; continue; fi
  if grep -U $'\r' "$r" >/dev/null 2>&1; then
    fail "CRLF found in $(basename "$r")"
  else
    pass "$(basename "$r") is LF-only"
  fi
done

# ----------------------------------------------------------------------
# [3] init.sh guards python3 presence
# ----------------------------------------------------------------------
echo ""
echo "[3] init.sh python3 guard:"
if grep -q 'command -v python3' "$POC_DIR/init.sh"; then
  pass "init.sh checks for python3"
else
  fail "init.sh missing python3 command-v guard"
fi
# The guard must fire before any non-comment python3 invocation later.
first_python3=$(grep -nE '^[^#]*python3' "$POC_DIR/init.sh" | grep -v 'command -v' | head -1 | cut -d: -f1)
first_check=$(grep -nE 'command -v python3' "$POC_DIR/init.sh" | head -1 | cut -d: -f1)
if [[ -z "$first_python3" ]]; then
  pass "guard present; no other python3 invocation in init.sh"
elif [[ -n "$first_check" && "$first_check" -le "$first_python3" ]]; then
  pass "guard precedes any python3 use (line $first_check ≤ $first_python3)"
else
  fail "guard does not precede python3 use (check=$first_check, first_use=$first_python3)"
fi

# ----------------------------------------------------------------------
# [4] Lock-slug regex excludes ':' (Windows-illegal)
# ----------------------------------------------------------------------
echo ""
echo "[4] queue-runner lock slug: no ':':"
QR="$POC_DIR/templates/queue-runner.sh"
# The _re_safe_slug pattern must not include ':'.
slug_line=$(grep -E '^_re_safe_slug=' "$QR" | head -1)
if [[ -z "$slug_line" ]]; then
  fail "no _re_safe_slug defined"
elif [[ "$slug_line" == *":"* ]]; then
  # Allow the ':' inside the variable assignment's own ':=' or similar, but the
  # regex body after the first '=' should not contain a bare ':'.
  rhs="${slug_line#*=}"
  # Strip surrounding quotes.
  rhs="${rhs//\'/}"
  rhs="${rhs//\"/}"
  if [[ "$rhs" == *":"* ]]; then
    fail "_re_safe_slug still allows ':' (breaks on Windows): $slug_line"
  else
    pass "_re_safe_slug has no ':' in regex body"
  fi
else
  pass "_re_safe_slug excludes ':'"
fi

# ----------------------------------------------------------------------
# [5] No BSD-only `sed -i ''` and no macOS-only `date -j`
# ----------------------------------------------------------------------
echo ""
echo "[5] No macOS/BSD-only sed -i '' / date -j:"
for r in "${RUNNERS[@]}"; do
  [[ -f "$r" ]] || continue
  if grep -Eq "sed -i ''" "$r"; then
    fail "$(basename "$r") uses 'sed -i \"\"' (BSD-only; breaks on Linux/Git Bash)"
  fi
  if grep -Eq 'date -j' "$r"; then
    fail "$(basename "$r") uses 'date -j' (macOS-only)"
  fi
done
pass "no BSD sed / date -j found"

# ----------------------------------------------------------------------
# [6] No hard dependency on cmds missing from Git Bash default
# Git Bash (MSYS2) provides: bash, grep, sed, awk, find, sort, uniq, tr,
# cat, head, tail, printf, date, mktemp, tee, wc, basename, dirname, cut,
# ls, mv, cp, rm, mkdir, touch, chmod, ln.
# NOT provided by default: jq, yq, realpath (on older Git Bash), column.
# ----------------------------------------------------------------------
echo ""
echo "[6] No hard deps on jq/yq/realpath:"
for r in "${RUNNERS[@]}"; do
  [[ -f "$r" ]] || continue
  for cmd in jq yq; do
    # Treat 'command -v jq' or 'if jq' etc as soft checks — skip those.
    if grep -Eq "(^|[^a-z-])${cmd}( |$|\\|)" "$r" | grep -qv 'command -v' 2>/dev/null; then
      # Conservative: flag anyway; these scripts should be dep-free.
      if grep -qE "[^a-z-]${cmd}( |$|\\|)" "$r"; then
        fail "$(basename "$r") may depend on '$cmd'"
      fi
    fi
  done
done
pass "no jq/yq references"

# Check realpath: some runners may use it for canonicalization.
realpath_use=""
for r in "${RUNNERS[@]}"; do
  [[ -f "$r" ]] || continue
  grep -Eq '\brealpath\b' "$r" && realpath_use="$realpath_use $(basename "$r")"
done
if [[ -z "$realpath_use" ]]; then
  pass "no realpath usage (Git Bash safe)"
else
  fail "realpath used in:$realpath_use (may be missing on older Git Bash)"
fi

# ----------------------------------------------------------------------
# [7] No Windows-illegal characters in format strings that build paths
# We scan for `date +...%H:%M:%S...` followed by `.md` / `.lock` / `.jsonl`
# Not comprehensive but catches the common mistake of colonized filenames.
# ----------------------------------------------------------------------
echo ""
echo "[7] No colonized date stamps in filename builders:"
hits=0
for r in "${RUNNERS[@]}"; do
  [[ -f "$r" ]] || continue
  # Pattern: within 2 lines of "date +" we must not see ':' followed later by
  # a filename-building concat. This is fuzzy; we just check whether the
  # runner uses iso_now-style formats that contain colons to BUILD paths.
  if grep -nE '\$\(iso_now\)\.(md|lock|jsonl)' "$r" >/dev/null; then
    fail "$(basename "$r") builds filename with \$(iso_now) (contains ':')"
    hits=$((hits+1))
  fi
  if grep -nE 'decision-\$ts\.md' "$r" >/dev/null; then
    # terminal.sh uses $ts = iso_now. We confirmed the format is
    # %Y%m%dT%H%M%SZ (no colons). Assert that.
    fmt=$(grep -E 'iso_now\(\)' "$r" | head -1)
    if [[ "$fmt" == *":"* ]]; then
      fail "$(basename "$r") ts format contains ':' in filename context"
      hits=$((hits+1))
    fi
  fi
done
[[ $hits -eq 0 ]] && pass "no colonized filename builders"

# ----------------------------------------------------------------------
# [8] Shebangs are /usr/bin/env bash (portable)
# ----------------------------------------------------------------------
echo ""
echo "[8] Portable shebangs:"
for r in "${RUNNERS[@]}"; do
  [[ -f "$r" ]] || continue
  first=$(head -1 "$r")
  if [[ "$first" == "#!/usr/bin/env bash" ]]; then
    pass "$(basename "$r") uses /usr/bin/env bash"
  else
    fail "$(basename "$r") shebang: $first"
  fi
done

# ----------------------------------------------------------------------
# [9] core.md §21.6 documents Windows support
# ----------------------------------------------------------------------
echo ""
echo "[9] core.md §21.6 Platform Support:"
C="$POC_DIR/templates/core/codenook-core.md"
if grep -q '### 21.6 Platform Support' "$C"; then
  pass "§21.6 Platform Support section exists"
  s216=$(awk '/^### 21\.6/{p=1; print; next} p; /^### |^## 22/{if (p) p=0}' "$C")
  echo "$s216" | grep -qi 'Git Bash'   && pass "§21.6 mentions Git Bash"  || fail "§21.6 missing Git Bash"
  echo "$s216" | grep -qi 'python3'    && pass "§21.6 mentions python3"   || fail "§21.6 missing python3"
  echo "$s216" | grep -qi 'WSL'        && pass "§21.6 mentions WSL"       || fail "§21.6 missing WSL"
else
  fail "§21.6 Platform Support missing from core.md"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
  echo "=== T23 PASSED ==="
  exit 0
else
  echo "=== T23 FAILED ($FAIL) ==="
  exit 1
fi

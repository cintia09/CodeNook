#!/usr/bin/env bash
# CodeNook v0.11.2 — top-level installer.
#
# Usage:
#   bash install.sh                       # install into $PWD
#   bash install.sh <workspace_path>      # install into a specific workspace
#   bash install.sh --dry-run [<path>]    # run install gates, do not commit
#   bash install.sh --upgrade [<path>]    # allow re-install of existing plugin
#   bash install.sh --plugin <id> [<path>]  # plugin id under plugins/ (default: development)
#   bash install.sh --no-claude-md [<path>] # skip CLAUDE.md augmentation
#   bash install.sh --check [<path>]      # report install state of a workspace
#   bash install.sh --help                # show this help
#
# Behaviour:
#   1. Runs the kernel installer (skills/codenook-core/install.sh) which
#      stages the requested plugin into <workspace>/.codenook/plugins/<id>/
#      and updates <workspace>/.codenook/state.json. Idempotent (G03/G04).
#   2. Augments the workspace CLAUDE.md with a clearly delimited
#      <!-- codenook:begin --> ... <!-- codenook:end --> bootloader block
#      (DR-006). The block is replaced verbatim on re-install; user content
#      outside the markers is never touched. If CLAUDE.md does not exist
#      a stub is created containing only the block.
#
# Exit codes:
#   0  installed (or dry-run pass)
#   1  any gate failed
#   2  usage / IO error
#   3  already installed (without --upgrade)

set -euo pipefail

VERSION="0.11.2"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PLUGIN="development"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  cat <<EOF
CodeNook installer v${VERSION}

Usage:
  bash install.sh [<workspace_path>]                  install plugin into workspace
  bash install.sh --dry-run [<workspace_path>]        gates only, no commit
  bash install.sh --upgrade [<workspace_path>]        allow re-install
  bash install.sh --plugin <id> [<workspace_path>]    plugin id (default: ${DEFAULT_PLUGIN})
  bash install.sh --no-claude-md [<workspace_path>]   skip CLAUDE.md augmentation
  bash install.sh --check [<workspace_path>]          report install state
  bash install.sh --help                              show this help

When <workspace_path> is omitted, the current directory is used.
EOF
}

# ── arg parsing ──────────────────────────────────────────────────────────
WORKSPACE=""
PLUGIN_ID="$DEFAULT_PLUGIN"
DRY_RUN=""
UPGRADE=""
CHECK_ONLY=0
AUGMENT_CLAUDE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN="--dry-run"; shift ;;
    --upgrade) UPGRADE="--upgrade"; shift ;;
    --plugin)  PLUGIN_ID="${2:-}"; shift 2 ;;
    --no-claude-md) AUGMENT_CLAUDE=0; shift ;;
    --check)   CHECK_ONLY=1; shift ;;
    --) shift; if [ $# -gt 0 ]; then WORKSPACE="$1"; shift; fi ;;
    -*) err "unknown option: $1"; usage >&2; exit 2 ;;
    *)
      if [ -z "$WORKSPACE" ]; then
        WORKSPACE="$1"; shift
      else
        err "unexpected positional arg: $1"; usage >&2; exit 2
      fi
      ;;
  esac
done

if [ -z "$WORKSPACE" ]; then
  WORKSPACE="$PWD"
fi
if [ ! -d "$WORKSPACE" ]; then
  err "workspace path does not exist: $WORKSPACE"; exit 2
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

KERNEL_INSTALL="$SELF_DIR/skills/codenook-core/install.sh"
PLUGIN_SRC="$SELF_DIR/plugins/$PLUGIN_ID"

# ── check-only mode ──────────────────────────────────────────────────────
check_workspace() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 CodeNook v${VERSION} — workspace status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Workspace : $WORKSPACE"
  local state_file="$WORKSPACE/.codenook/state.json"
  if [ -f "$state_file" ]; then
    info ".codenook/state.json present"
    cat "$state_file" | sed 's/^/    /'
  else
    warn "no .codenook/state.json — workspace not initialised"
  fi
  if [ -f "$WORKSPACE/CLAUDE.md" ] && grep -q "codenook:begin" "$WORKSPACE/CLAUDE.md" 2>/dev/null; then
    info "CLAUDE.md has codenook bootloader block"
  else
    warn "CLAUDE.md has no codenook bootloader block"
  fi
}
if [ "$CHECK_ONLY" -eq 1 ]; then
  check_workspace
  exit 0
fi

# ── pre-flight ───────────────────────────────────────────────────────────
if [ ! -x "$KERNEL_INSTALL" ]; then
  err "kernel installer not found or not executable: $KERNEL_INSTALL"; exit 2
fi
if [ ! -d "$PLUGIN_SRC" ]; then
  err "plugin source not found: $PLUGIN_SRC"; exit 2
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🤖 CodeNook v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Workspace : $WORKSPACE"
echo "  Plugin    : ${PLUGIN_ID} (from ${PLUGIN_SRC})"
[ -n "$DRY_RUN" ] && echo "  Mode      : DRY-RUN"
[ -n "$UPGRADE" ] && echo "  Mode      : UPGRADE"
echo ""

set +e
"$KERNEL_INSTALL" --src "$PLUGIN_SRC" --workspace "$WORKSPACE" $DRY_RUN $UPGRADE
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  err "kernel install exited with rc=$rc"
  exit "$rc"
fi
info "Plugin '$PLUGIN_ID' installed into $WORKSPACE/.codenook/"

# ── CLAUDE.md augmentation (DR-006) ──────────────────────────────────────
if [ -n "$DRY_RUN" ]; then
  echo "  [DRY-RUN] Would write CLAUDE.md bootloader block"
  exit 0
fi

if [ "$AUGMENT_CLAUDE" -eq 1 ]; then
  python3 "$SELF_DIR/skills/codenook-core/skills/builtin/_lib/claude_md_sync.py" \
    --workspace "$WORKSPACE" \
    --version "$VERSION" \
    --plugin "$PLUGIN_ID"
  info "CLAUDE.md bootloader block synced (idempotent)"
fi

echo ""
echo "  Quick start:"
echo "    cd \"$WORKSPACE\""
echo "    # In Claude Code or Copilot CLI session:"
echo "    \"CodeNook: start a new task\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

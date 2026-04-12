#!/usr/bin/env bash
set -euo pipefail

# CodeNook v4.0 Installer
# Usage: curl -sL https://raw.githubusercontent.com/cintia09/CodeNook/main/install.sh | bash

VERSION="latest"
REPO="https://github.com/cintia09/CodeNook.git"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/CodeNook.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}✓${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }

usage() {
    echo "CodeNook Installer v${VERSION}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --install     Install framework (default)"
    echo "  --check       Check installation status"
    echo "  --uninstall   Remove framework files"
    echo "  --dry-run     Preview changes without applying"
    echo "  -h, --help    Show this help"
}

# ── Download ──────────────────────────────────────────────

download() {
    echo "📥 Downloading framework..."
    local success=false

    # Method 1: Tarball (faster)
    local TARBALL_URL="https://github.com/cintia09/CodeNook/archive/refs/heads/main.tar.gz"
    if curl -sL --connect-timeout 10 --max-time 60 "$TARBALL_URL" | tar xz -C "$TMP_DIR" --strip-components=1 2>/dev/null; then
        [ -f "$TMP_DIR/install.sh" ] && [ -d "$TMP_DIR/skills" ] && success=true
    fi

    # Method 2: Git clone fallback
    if [ "$success" = false ]; then
        warn "Tarball failed, trying git clone..."
        rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
        git clone --depth 1 "$REPO" "$TMP_DIR" 2>/dev/null || error "Download failed. Check network."
        success=true
    fi

    [ -f "$TMP_DIR/VERSION" ] && VERSION=$(cat "$TMP_DIR/VERSION" | tr -d '[:space:]')
    info "Downloaded v${VERSION}"
}

# ── Install ──────────────────────────────────────────────

install_platform() {
    local dir="$1" name="$2" src="$TMP_DIR/skills"

    echo -e "  ${CYAN}${name}${NC} → ${dir}/skills/"

    # codenook-init (SKILL.md + templates/)
    mkdir -p "${dir}/skills/codenook-init/templates"
    cp "${src}/codenook-init/SKILL.md" "${dir}/skills/codenook-init/"
    cp "${src}/codenook-init/templates/"*.agent.md "${dir}/skills/codenook-init/templates/"

    # codenook-engine (SKILL.md + hitl-adapters/)
    mkdir -p "${dir}/skills/codenook-engine/hitl-adapters"
    cp "${src}/codenook-engine/SKILL.md" "${dir}/skills/codenook-engine/"
    cp "${src}/codenook-engine/hitl-adapters/"* "${dir}/skills/codenook-engine/hitl-adapters/"
    chmod +x "${dir}/skills/codenook-engine/hitl-adapters/"*.sh 2>/dev/null || true
    chmod +x "${dir}/skills/codenook-engine/hitl-adapters/"*.py 2>/dev/null || true
}

install() {
    local dry_run=${1:-false}

    if [ "$dry_run" = false ]; then
        download
    else
        echo "  [DRY RUN] Would download from GitHub"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🤖 CodeNook v${VERSION}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ "$dry_run" = true ]; then
        echo "  [DRY RUN] Would install:"
        echo "    ~/.copilot/skills/codenook-init/"
        echo "    ~/.copilot/skills/codenook-engine/"
        echo "    ~/.claude/skills/codenook-init/"
        echo "    ~/.claude/skills/codenook-engine/"
        return
    fi

    echo "📦 Installing skills..."

    # Copilot CLI
    if [ -d "${HOME}/.copilot" ] || command -v copilot &>/dev/null; then
        install_platform "${HOME}/.copilot" "Copilot CLI"
        info "Copilot CLI: 2 skills installed"
    else
        warn "Copilot CLI not detected (skipped)"
    fi

    # Claude Code
    if [ -d "${HOME}/.claude" ] || command -v claude &>/dev/null; then
        install_platform "${HOME}/.claude" "Claude Code"
        info "Claude Code: 2 skills installed"
    else
        warn "Claude Code not detected (skipped)"
    fi

    # Verify
    echo ""
    echo "🔍 Verifying..."
    check_install

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    info "Installed! v${VERSION}"
    echo ""
    echo "  What's installed:"
    echo "    codenook-init     — Initialize agent system in any project"
    echo "    codenook-engine   — Task routing, HITL gates, memory"
    echo "    5 agent templates — acceptor, designer, implementer, reviewer, tester"
    echo "    4 HITL adapters   — local-html, terminal, confluence, github-issue"
    echo ""
    echo "  Quick start:"
    echo "    cd your-project"
    echo '    "Initialize agent system"  → generates .github/agents/'
    echo '    "Create task <title>"      → add a task'
    echo '    "Run task T-001"           → start orchestration'
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Check ─────────────────────────────────────────────────

check_platform() {
    local dir="$1" name="$2"
    local ok=true
    echo -e "  ${CYAN}${name}${NC}:"

    if [ -f "${dir}/skills/codenook-init/SKILL.md" ]; then
        local templates=$(ls "${dir}/skills/codenook-init/templates/"*.agent.md 2>/dev/null | wc -l | tr -d ' ')
        echo "    codenook-init:    ✅ (${templates} templates)"
    else
        echo "    codenook-init:    ❌ missing"
        ok=false
    fi

    if [ -f "${dir}/skills/codenook-engine/SKILL.md" ]; then
        local adapters=$(ls "${dir}/skills/codenook-engine/hitl-adapters/"* 2>/dev/null | wc -l | tr -d ' ')
        echo "    codenook-engine:  ✅ (${adapters} HITL adapters)"
    else
        echo "    codenook-engine:  ❌ missing"
        ok=false
    fi

    $ok
}

check_install() {
    echo "🔍 Checking installation..."
    local any=false

    if [ -d "${HOME}/.copilot/skills" ]; then
        check_platform "${HOME}/.copilot" "Copilot CLI" && any=true
    fi
    if [ -d "${HOME}/.claude/skills" ]; then
        check_platform "${HOME}/.claude" "Claude Code" && any=true
    fi

    if [ "$any" = false ]; then
        warn "No installation found. Run: $0 --install"
    fi
}

# ── Uninstall ────────────────────────────────────────────

uninstall() {
    echo "🗑️ Uninstalling CodeNook..."

    for dir in "${HOME}/.copilot" "${HOME}/.claude"; do
        if [ -d "${dir}/skills/codenook-init" ] || [ -d "${dir}/skills/codenook-engine" ]; then
            echo "  Removing from ${dir}..."
            rm -rf "${dir}/skills/codenook-init"
            rm -rf "${dir}/skills/codenook-engine"
            info "Removed from $(basename $dir)"
        fi
    done

    echo ""
    echo "  ℹ️  Project-level files (.github/codenook/, .claude/codenook/) are not removed."
    echo "      Delete them manually per project if needed."
    info "Uninstall complete"
}

# ── Main ──────────────────────────────────────────────────

case "${1:-}" in
    --install|"")  install false ;;
    --check)       check_install ;;
    --uninstall)   uninstall ;;
    --dry-run)     install true ;;
    -h|--help)     usage ;;
    *)             echo "Unknown option: $1"; usage; exit 1 ;;
esac

#!/usr/bin/env bash
# init.sh — builtin "init" skill.
#
# Scaffolds the workspace memory skeleton in $PWD/.codenook/memory/:
#   knowledge/  skills/  history/  config.yaml
#
# Also installs a self-contained copy of the codenook-core kernel into
#   $PWD/.codenook/codenook-core/
# so the workspace can run the lifecycle protocol (router-agent,
# orchestrator-tick, hitl-adapter, extractor-batch, ...) without
# depending on the source repository being on disk.
#
# Idempotent: safe to re-run; existing files / directories are preserved
# (the kernel copy uses VERSION compare + atomic rename).

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SELF_DIR/../_lib" && pwd)"
CORE_DIR="$(cd "$SELF_DIR/../../.." && pwd)"

WS="${1:-$PWD}"

PYTHONPATH="$LIB_DIR" python3 - "$WS" "$CORE_DIR" <<'PY'
import sys, os, shutil, tempfile
import memory_layer as ml

ws, core_src = sys.argv[1], sys.argv[2]
ml.init_memory_skeleton(ws)

# Self-contained kernel install: copy <core_src>/* (minus tests/) to
# <ws>/.codenook/codenook-core/. Re-run is a no-op when VERSION matches.
dst = os.path.join(ws, ".codenook", "codenook-core")
src_version = ""
vp = os.path.join(core_src, "VERSION")
if os.path.isfile(vp):
    with open(vp, "r", encoding="utf-8") as f:
        src_version = f.read().strip()

dst_version = ""
dvp = os.path.join(dst, "VERSION")
if os.path.isfile(dvp):
    with open(dvp, "r", encoding="utf-8") as f:
        dst_version = f.read().strip()

if dst_version != src_version or not os.path.isdir(dst):
    EXCLUDE_DIRS = {"tests", "__pycache__", ".pytest_cache"}
    EXCLUDE_SUFFIX = (".pyc",)
    parent = os.path.dirname(dst)
    os.makedirs(parent, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=".codenook-core.", dir=parent)
    try:
        def _ignore(_dir, names):
            ignored = set()
            for n in names:
                if n in EXCLUDE_DIRS or n.endswith(EXCLUDE_SUFFIX):
                    ignored.add(n)
            return ignored
        # Copy core_src contents into staging (not core_src itself)
        for entry in os.listdir(core_src):
            if entry in EXCLUDE_DIRS:
                continue
            s = os.path.join(core_src, entry)
            d = os.path.join(staging, entry)
            if os.path.isdir(s):
                shutil.copytree(s, d, ignore=_ignore, symlinks=False)
            else:
                shutil.copy2(s, d)
        # Atomic swap
        if os.path.isdir(dst):
            backup = dst + ".old"
            if os.path.isdir(backup):
                shutil.rmtree(backup)
            os.replace(dst, backup)
            os.replace(staging, dst)
            shutil.rmtree(backup, ignore_errors=True)
        else:
            os.replace(staging, dst)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
PY

# Append the snapshot file to a workspace-local .gitignore so it is not
# accidentally committed.
gi="$WS/.codenook/memory/.gitignore"
if [ ! -f "$gi" ]; then
  printf '.index-snapshot.json\n' > "$gi"
elif ! grep -qx '.index-snapshot.json' "$gi"; then
  printf '.index-snapshot.json\n' >> "$gi"
fi

# workspace-local .gitignore for the task-chain snapshot
mkdir -p "$WS/.codenook/tasks"
gi="$WS/.codenook/tasks/.gitignore"
if [ ! -f "$gi" ]; then
  printf '.chain-snapshot.json\n' > "$gi"
elif ! grep -qx '.chain-snapshot.json' "$gi"; then
  printf '.chain-snapshot.json\n' >> "$gi"
fi

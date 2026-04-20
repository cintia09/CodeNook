"""Stage the codenook-core kernel into ``<ws>/.codenook/codenook-core``.

Replaces ``skills/codenook-core/init.sh`` and the inline VERSION-compare
+ atomic-rename logic that used to live there.
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

# What we never copy into the staged kernel.
_EXCLUDE_DIRS = {"tests", "__pycache__", ".pytest_cache"}
_EXCLUDE_SUFFIXES = (".pyc",)


def _ignore(_dir: str, names: list[str]) -> set[str]:
    out: set[str] = set()
    for n in names:
        if n in _EXCLUDE_DIRS or n.endswith(_EXCLUDE_SUFFIXES):
            out.add(n)
    return out


def _read_version(p: Path) -> str:
    if p.is_file():
        try:
            return p.read_text(encoding="utf-8").strip()
        except Exception:
            pass
    return ""


def stage_kernel(core_src: Path, workspace: Path) -> Path:
    """Copy ``<core_src>/*`` (minus tests/) into
    ``<workspace>/.codenook/codenook-core/``. Idempotent: when the
    staged ``VERSION`` file matches ``<core_src>/VERSION`` we skip.
    Returns the staged kernel root.
    """
    dst = workspace / ".codenook" / "codenook-core"
    src_version = _read_version(core_src / "VERSION")
    dst_version = _read_version(dst / "VERSION")

    if dst.is_dir() and dst_version and dst_version == src_version:
        return dst

    parent = dst.parent
    parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".codenook-core.", dir=str(parent)))
    try:
        for entry in os.listdir(core_src):
            if entry in _EXCLUDE_DIRS:
                continue
            s = core_src / entry
            d = staging / entry
            if s.is_dir():
                shutil.copytree(s, d, ignore=_ignore, symlinks=False)
            else:
                shutil.copy2(s, d)

        if dst.is_dir():
            backup = dst.with_name(dst.name + ".old")
            if backup.is_dir():
                shutil.rmtree(backup, ignore_errors=True)
            os.replace(dst, backup)
            os.replace(staging, dst)
            shutil.rmtree(backup, ignore_errors=True)
        else:
            os.replace(staging, dst)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise

    return dst


def init_memory_skeleton(workspace: Path) -> None:
    """Create the ``.codenook/memory`` skeleton and gitignore stubs."""
    mem = workspace / ".codenook" / "memory"
    for sub in ("knowledge", "skills", "history", "_pending"):
        (mem / sub).mkdir(parents=True, exist_ok=True)
        gk = mem / sub / ".gitkeep"
        if not gk.is_file():
            gk.write_text("", encoding="utf-8")

    gi = mem / ".gitignore"
    _append_unique(gi, ".index-snapshot.json")

    tasks = workspace / ".codenook" / "tasks"
    tasks.mkdir(parents=True, exist_ok=True)
    _append_unique(tasks / ".gitignore", ".chain-snapshot.json")


def _append_unique(path: Path, line: str) -> None:
    line = line.rstrip("\n")
    if not path.is_file():
        path.write_text(line + "\n", encoding="utf-8")
        return
    existing = [ln.rstrip("\n") for ln in path.read_text(encoding="utf-8").splitlines()]
    if line in existing:
        return
    with path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")

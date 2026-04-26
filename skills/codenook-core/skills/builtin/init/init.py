#!/usr/bin/env python3
"""init/init.py — Python entry equivalent to ``init.sh``.

Scaffolds the workspace memory skeleton and installs the codenook-core kernel.
CWD is irrelevant; the first positional argument is the target workspace path
(defaults to CWD if omitted).
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB_DIR = (HERE / "../_lib").resolve()
CORE_DIR = (HERE / "../../..").resolve()

sys.path.insert(0, str(LIB_DIR))
import memory_layer as ml  # noqa: E402


def _install_kernel(ws: str, core_src: str) -> None:
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

            for entry in os.listdir(core_src):
                if entry in EXCLUDE_DIRS:
                    continue
                s = os.path.join(core_src, entry)
                d = os.path.join(staging, entry)
                if os.path.isdir(s):
                    shutil.copytree(s, d, ignore=_ignore, symlinks=False)
                else:
                    shutil.copy2(s, d)
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


def _ensure_gitignore(path: str, entry: str) -> None:
    if not os.path.isfile(path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(entry + "\n")
    else:
        with open(path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
        if entry not in lines:
            with open(path, "a", encoding="utf-8") as f:
                f.write(entry + "\n")


def main(argv=None) -> int:
    args = (argv if argv is not None else sys.argv)[1:]
    ws = args[0] if args else os.getcwd()
    core_src = str(CORE_DIR)

    ml.init_memory_skeleton(ws)
    _install_kernel(ws, core_src)

    gi_memory = os.path.join(ws, ".codenook", "memory", ".gitignore")
    _ensure_gitignore(gi_memory, ".index-snapshot.json")

    tasks_dir = os.path.join(ws, ".codenook", "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    gi_tasks = os.path.join(tasks_dir, ".gitignore")
    _ensure_gitignore(gi_tasks, ".chain-snapshot.json")

    return 0


if __name__ == "__main__":
    sys.exit(main())

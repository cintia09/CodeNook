#!/usr/bin/env python3
"""CodeNook v6 — pre-commit hook template (M9.8).

Python port of the legacy ``pre-commit-hook.sh``. Install per checkout::

    cp skills/codenook-core/templates/pre-commit-hook.py \\
       .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit

The hook fails closed when:
  1. plugins/ is being modified outside of an explicit upgrade
     (delegated to _lib/plugin_readonly.py — see M9.7).
  2. CLAUDE.md is malformed or violates the M9.7 memory protocol.
  3. Any staged blob contains a known secret (AWS keys, OpenAI / GH
     PATs, RSA private keys, internal IPs, DB connection strings —
     see _lib/secret_scan.py).

Exit 0 -> commit proceeds. Exit non-zero -> commit is rejected.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


def fail(msg: str) -> None:
    sys.stderr.write(f"[pre-commit] REJECTED: {msg}\n")
    sys.exit(1)


def git_output(*args: str) -> str:
    res = subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    )
    return res.stdout


def main() -> int:
    repo_root = Path(git_output("rev-parse", "--show-toplevel").strip())
    lib_dir = Path(
        os.environ.get(
            "CN_LIB_DIR",
            str(repo_root / "skills" / "codenook-core" / "skills" / "builtin" / "_lib"),
        )
    )

    # 0. fast staged-plugins gate (anchored at repo root)
    staged_all = git_output(
        "diff", "--cached", "--name-only", "--diff-filter=AM"
    ).splitlines()
    staged_plugins = [p for p in staged_all if re.match(r"^plugins/", p)]
    if staged_plugins:
        fail(
            "staged write under plugins/ — read-only invariant violated:\n"
            + "\n".join(staged_plugins)
        )

    if not lib_dir.is_dir():
        # CodeNook core not present in this checkout — staged-plugins
        # gate above has already run.
        return 0

    env = os.environ.copy()
    env["PYTHONPATH"] = str(lib_dir) + (
        os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
    )

    # 1. plugin readonly (static checker)
    pr_script = lib_dir / "plugin_readonly.py"
    res = subprocess.run(
        ["python3", str(pr_script), "--target", str(repo_root), "--json"],
        env=env, capture_output=True, text=True,
    )
    if res.returncode != 0:
        sys.stderr.write("[pre-commit] plugin_readonly check failed:\n")
        sys.stderr.write(res.stdout)
        sys.stderr.write(res.stderr)
        fail("plugin tree may not be modified by extractors / agents")

    # 2. CLAUDE.md lint
    claude_md = repo_root / "CLAUDE.md"
    if claude_md.is_file():
        lint_script = lib_dir / "claude_md_linter.py"
        res = subprocess.run(
            ["python3", str(lint_script), "--check-claude-md", str(claude_md)],
            env=env, capture_output=True, text=True,
        )
        if res.returncode != 0:
            sys.stderr.write("[pre-commit] CLAUDE.md linter found errors:\n")
            sys.stderr.write(res.stdout)
            sys.stderr.write(res.stderr)
            fail("CLAUDE.md linter errors must be fixed before commit")

    # 3. secret scan
    if staged_all:
        sys.path.insert(0, str(lib_dir))
        try:
            from secret_scan import scan_secrets  # type: ignore
        except Exception as exc:
            fail(f"cannot import secret_scan from {lib_dir}: {exc}")

        hits: list[str] = []
        for rel in staged_all:
            rel = rel.strip()
            if not rel:
                continue
            p = repo_root / rel
            if not p.is_file():
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            hit, rule = scan_secrets(text)
            if hit:
                hits.append(f"{rel}: {rule}")
        if hits:
            sys.stderr.write("[pre-commit] secret scanner hits:\n")
            sys.stderr.write("\n".join(hits) + "\n")
            fail("remove the secret(s) above before committing")

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""sec-audit core logic: scan a workspace for secret patterns, permission
issues on .codenook/secrets.yaml, and world-writable files in .codenook/.

Inputs (env):
  CN_WORKSPACE  absolute or relative path
  CN_JSON       "1" to emit JSON on stdout
  CN_PATTERNS   path to patterns.txt

Exit:
  0 no findings
  1 findings
"""
from __future__ import annotations

import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

SKIP_DIR_NAMES = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build"}
BINARY_CHECK_BYTES = 2048


def load_patterns(path: Path) -> list:
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        try:
            out.append(re.compile(s))
        except re.error:
            pass
    return out


def list_gitignored(ws: Path) -> set:
    """Return set of absolute paths that git considers ignored.
    Silently empty if not a git repo or git unavailable.
    """
    try:
        r = subprocess.run(
            ["git", "-C", str(ws), "ls-files", "--others", "--ignored",
             "--exclude-standard", "--directory"],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode != 0:
            return set()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return set()
    paths = set()
    for rel in r.stdout.splitlines():
        rel = rel.strip()
        if not rel:
            continue
        p = (ws / rel).resolve()
        paths.add(str(p))
    return paths


def is_under_ignored(p: Path, ignored: set) -> bool:
    ps = str(p.resolve())
    for ig in ignored:
        if ps == ig or ps.startswith(ig.rstrip("/") + "/"):
            return True
    return False


def looks_binary(b: bytes) -> bool:
    if b"\x00" in b:
        return True
    return False


def scan_file(path: Path, patterns: list, findings: list) -> None:
    try:
        with path.open("rb") as f:
            head = f.read(BINARY_CHECK_BYTES)
        if looks_binary(head):
            return
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return
    for lineno, line in enumerate(text.splitlines(), start=1):
        for rx in patterns:
            if rx.search(line):
                findings.append({
                    "type": "secret",
                    "path": str(path),
                    "line": lineno,
                    "severity": "high",
                })
                break


def scan_workspace(ws: Path, patterns: list, findings: list) -> None:
    ignored = list_gitignored(ws)
    for root, dirs, files in os.walk(ws):
        # prune
        dirs[:] = [d for d in dirs if d not in SKIP_DIR_NAMES]
        rootp = Path(root)
        # gitignore pruning
        dirs[:] = [d for d in dirs if not is_under_ignored(rootp / d, ignored)]
        for fname in files:
            fp = rootp / fname
            if is_under_ignored(fp, ignored):
                continue
            scan_file(fp, patterns, findings)


def check_secrets_yaml(ws: Path, findings: list) -> None:
    sy = ws / ".codenook" / "secrets.yaml"
    if not sy.is_file():
        return
    try:
        mode = stat.S_IMODE(sy.stat().st_mode)
    except OSError:
        return
    if mode != 0o600:
        findings.append({
            "type": "permission",
            "path": str(sy),
            "severity": "medium",
            "mode": f"{mode:o}",
            "expected": "600",
        })


def check_world_writable(ws: Path, findings: list) -> None:
    cn = ws / ".codenook"
    if not cn.is_dir():
        return
    for root, _dirs, files in os.walk(cn):
        for fname in files:
            fp = Path(root) / fname
            try:
                mode = stat.S_IMODE(fp.stat().st_mode)
            except OSError:
                continue
            if mode & 0o002:
                findings.append({
                    "type": "world-writable",
                    "path": str(fp),
                    "severity": "high",
                    "mode": f"{mode:o}",
                })


def main() -> int:
    ws = Path(os.environ["CN_WORKSPACE"]).resolve()
    as_json = os.environ.get("CN_JSON") == "1"
    patterns_path = Path(os.environ["CN_PATTERNS"])

    patterns = load_patterns(patterns_path)
    findings: list = []

    scan_workspace(ws, patterns, findings)
    check_secrets_yaml(ws, findings)
    check_world_writable(ws, findings)

    ok = len(findings) == 0

    if as_json:
        print(json.dumps({"ok": ok, "findings": findings}, indent=2))

    for f in findings:
        t = f["type"]
        if t == "secret":
            print(f"finding: secret match at {f['path']}:{f['line']}", file=sys.stderr)
        elif t == "permission":
            print(f"finding: {f['path']} mode {f['mode']} (expected {f['expected']})", file=sys.stderr)
        elif t == "world-writable":
            print(f"finding: world-writable {f['path']} mode {f['mode']}", file=sys.stderr)

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

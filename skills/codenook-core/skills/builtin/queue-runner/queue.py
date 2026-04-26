#!/usr/bin/env python3
"""queue-runner/queue.py — Python entry equivalent to ``queue.sh``."""
from __future__ import annotations
import argparse, os, runpy, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

def _find_workspace(start: Path):
    for p in [start, *start.parents]:
        if (p / ".codenook").is_dir():
            return p
    return None

def main(argv=None) -> int:
    raw = list(argv if argv is not None else sys.argv[1:])
    if not raw:
        print("queue.py: subcommand required (enqueue|dequeue|peek|list|size)", file=sys.stderr)
        return 2
    ap = argparse.ArgumentParser(prog="queue", add_help=False)
    ap.add_argument("subcmd")
    ap.add_argument("--queue", required=True)
    ap.add_argument("--payload", default="")
    ap.add_argument("--filter", default="", dest="filter_val")
    ap.add_argument("--workspace", default="")
    ap.add_argument("-h", "--help", action="store_true")
    args, _ = ap.parse_known_args(raw)
    if args.help:
        skill_md = HERE / "SKILL.md"
        if skill_md.exists():
            lines = skill_md.read_text(encoding="utf-8").splitlines()
            print("\n".join(lines[:30]))
        return 0
    workspace = args.workspace or os.environ.get("CODENOOK_WORKSPACE", "")
    if not workspace:
        ws = _find_workspace(Path.cwd())
        if ws is None:
            print("queue.py: could not locate workspace (set --workspace or CODENOOK_WORKSPACE)", file=sys.stderr)
            return 2
        workspace = str(ws)
    if not Path(workspace).is_dir():
        print(f"queue.py: workspace not found: {workspace}", file=sys.stderr)
        return 2
    if args.subcmd == "enqueue" and not args.payload:
        print("queue.py: enqueue requires --payload", file=sys.stderr)
        return 2
    os.environ["PYTHONIOENCODING"] = "utf-8"
    os.environ["CN_SUBCMD"] = args.subcmd
    os.environ["CN_QUEUE"] = args.queue
    os.environ["CN_PAYLOAD"] = args.payload
    os.environ["CN_FILTER"] = args.filter_val
    os.environ["CN_WORKSPACE"] = workspace
    helper = HERE / "_queue.py"
    sys.argv = [str(helper)]
    try:
        runpy.run_path(str(helper), run_name="__main__")
    except SystemExit as e:
        code = e.code
        return int(code) if isinstance(code, int) else (0 if code is None else 1)
    return 0

if __name__ == "__main__":
    sys.exit(main())

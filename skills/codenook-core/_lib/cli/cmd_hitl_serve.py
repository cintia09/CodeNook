"""``codenook hitl serve`` — stdlib HTTP UI for the HITL queue.

A single-process, stdlib-only web frontend so an operator can review
+ decide pending HITL entries from a browser without leaving CodeNook
or installing a JS framework. Intended for solo / small-team use; do
not expose to the public internet (no auth, no CSRF).

Routes
======

* ``GET  /``                    — list pending entries (and recently
                                  decided) with links to /entry/<id>
* ``GET  /entry/<id>``          — render the entry's prompt + a tiny
                                  decision form
* ``GET  /entry/<id>/raw``      — raw JSON of the entry
* ``POST /entry/<id>/decide``   — form action; calls the existing
                                  ``hitl-adapter/_hitl.py`` helper
                                  with the same env vars
                                  ``cmd_hitl.run`` uses, then 303s
                                  back to ``/``

Implementation note
===================

The decision write is delegated to the same helper subprocess
the CLI ``hitl decide`` path invokes (``hitl-adapter/_hitl.py``).
This keeps a single source of truth for state-mutation logic — the
HTTP layer is pure rendering + form-to-env translation.
"""
from __future__ import annotations

import getpass
import html
import http.server
import json
import os
import socketserver
import subprocess
import sys
import urllib.parse
from pathlib import Path
from typing import Sequence

from . import _subproc
from .config import CodenookContext


HELP = """\
Usage: codenook hitl serve [--port N] [--bind addr]

Runs a stdlib HTTP server on <bind>:<port> (default 127.0.0.1:8765)
serving a tiny review UI for pending HITL entries.

This is intentionally minimal: no auth, no CSRF, no TLS. Bind to
127.0.0.1 (default) and tunnel through SSH if you need remote
access. Stop with Ctrl-C.

Routes:
  GET  /                       list of pending + recent entries
  GET  /entry/<id>             prompt + decision form
  GET  /entry/<id>/raw         raw JSON
  POST /entry/<id>/decide      form action (decision/comment fields)
"""


_QUEUE_REL = Path(".codenook") / "hitl-queue"
_CONSUMED_REL = _QUEUE_REL / "_consumed"


def _entries(workspace: Path, consumed: bool = False) -> list[dict]:
    qdir = workspace / (_CONSUMED_REL if consumed else _QUEUE_REL)
    if not qdir.is_dir():
        return []
    out: list[dict] = []
    for jf in sorted(qdir.glob("*.json")):
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, dict):
            continue
        out.append(data)
    return out


def _render_index(workspace: Path) -> bytes:
    pending = _entries(workspace, consumed=False)
    consumed = _entries(workspace, consumed=True)[-20:]

    def _row(e: dict, decided: bool) -> str:
        eid = html.escape(str(e.get("id", "")))
        gate = html.escape(str(e.get("gate", "")))
        task = html.escape(str(e.get("task_id", "")))
        decision = html.escape(str(e.get("decision", "—")))
        link = f'<a href="/entry/{eid}">{eid}</a>'
        return (f"<tr><td>{link}</td><td>{task}</td><td>{gate}</td>"
                f"<td>{decision if decided else '<i>pending</i>'}</td></tr>")

    body = ["<!doctype html><html><head><meta charset='utf-8'>"
            "<title>codenook hitl</title>"
            "<style>body{font-family:system-ui,sans-serif;max-width:960px;"
            "margin:2em auto;padding:0 1em}"
            "table{width:100%;border-collapse:collapse;margin:1em 0}"
            "th,td{border-bottom:1px solid #ddd;padding:6px 8px;"
            "text-align:left}"
            "h1,h2{border-bottom:2px solid #333}</style></head><body>",
            "<h1>codenook hitl</h1>",
            f"<p>Workspace: <code>{html.escape(str(workspace))}</code></p>",
            "<h2>Pending</h2>"]
    if pending:
        body.append("<table><tr><th>id</th><th>task</th><th>gate</th>"
                    "<th>status</th></tr>")
        body.extend(_row(e, decided=False) for e in pending)
        body.append("</table>")
    else:
        body.append("<p><i>(no pending entries)</i></p>")

    body.append("<h2>Recently decided</h2>")
    if consumed:
        body.append("<table><tr><th>id</th><th>task</th><th>gate</th>"
                    "<th>decision</th></tr>")
        body.extend(_row(e, decided=True) for e in reversed(consumed))
        body.append("</table>")
    else:
        body.append("<p><i>(none)</i></p>")

    body.append("</body></html>")
    return "".join(body).encode("utf-8")


def _find_entry(workspace: Path, eid: str) -> tuple[dict | None, bool]:
    """Return (entry_dict, is_pending). Search pending first, then consumed."""
    safe = _safe_id(eid)
    if safe is None:
        return None, False
    for consumed in (False, True):
        f = workspace / (_CONSUMED_REL if consumed else _QUEUE_REL) / (safe + ".json")
        if f.is_file():
            try:
                return json.loads(f.read_text(encoding="utf-8")), not consumed
            except Exception:
                return None, not consumed
    return None, False


def _safe_id(eid: str) -> str | None:
    """Reject path-traversal / odd characters in the entry id."""
    import re
    if not re.fullmatch(r"[A-Za-z0-9._\-\u4e00-\u9fff]+", eid):
        return None
    return eid


def _render_entry(workspace: Path, eid: str) -> tuple[int, bytes]:
    entry, pending = _find_entry(workspace, eid)
    if entry is None:
        return 404, b"<h1>404 entry not found</h1>"

    prompt = html.escape(str(entry.get("prompt", "")))
    eid_h = html.escape(eid)
    decision_block = ""
    if pending:
        decision_block = (
            f"<h2>Decide</h2>"
            f'<form method="POST" action="/entry/{eid_h}/decide">'
            f'<p>Decision: '
            f'<select name="decision">'
            f'<option value="approve">approve</option>'
            f'<option value="needs_changes">needs_changes</option>'
            f'<option value="reject">reject</option>'
            f'</select></p>'
            f'<p>Reviewer: <input type="text" name="reviewer" '
            f'value="{html.escape(os.environ.get("USER") or getpass.getuser() or "cli")}"></p>'
            f'<p>Comment:<br>'
            f'<textarea name="comment" rows="4" cols="80"></textarea></p>'
            f'<p><button type="submit">Submit</button></p>'
            f'</form>')
    else:
        decision_block = (
            f"<h2>Decision (recorded)</h2>"
            f"<p>{html.escape(str(entry.get('decision', '?')))} — "
            f"by {html.escape(str(entry.get('reviewer', '?')))} "
            f"at {html.escape(str(entry.get('decided_at', '?')))}</p>"
            f"<p><i>{html.escape(str(entry.get('comment', '')))}</i></p>")

    body = ("<!doctype html><html><head><meta charset='utf-8'>"
            f"<title>{eid_h}</title>"
            "<style>body{font-family:system-ui,sans-serif;max-width:960px;"
            "margin:2em auto;padding:0 1em}"
            "pre{white-space:pre-wrap;background:#f6f6f6;padding:1em;"
            "border-radius:4px}</style></head><body>"
            f"<p><a href='/'>← back</a> · "
            f"<a href='/entry/{eid_h}/raw'>raw json</a></p>"
            f"<h1>{eid_h}</h1>"
            f"<pre>{prompt}</pre>"
            f"{decision_block}"
            "</body></html>").encode("utf-8")
    return 200, body


def _decide(
    ctx: CodenookContext, helper: Path,
    eid: str, decision: str, reviewer: str, comment: str,
) -> tuple[int, str]:
    extra = {
        "CN_SUBCMD": "decide",
        "CN_ID": eid,
        "CN_DECISION": decision,
        "CN_REVIEWER": reviewer,
        "CN_COMMENT": comment,
        "CN_WORKSPACE": str(ctx.workspace),
        "CN_JSON": "0",
    }
    cp = subprocess.run(
        [sys.executable, str(helper)],
        env=_subproc.kernel_env(ctx, extra),
        capture_output=True, text=True,
    )
    return cp.returncode, (cp.stdout + cp.stderr)


def _make_handler(ctx: CodenookContext, helper: Path):
    workspace = ctx.workspace

    class Handler(http.server.BaseHTTPRequestHandler):
        # Quieter access log.
        def log_message(self, fmt, *a):
            sys.stderr.write(f"  hitl-serve: {self.address_string()} "
                             f"{fmt % a}\n")

        def _send(self, status: int, body: bytes,
                  ctype: str = "text/html; charset=utf-8") -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):  # noqa: N802
            path = urllib.parse.urlparse(self.path).path
            if path in ("/", "/index.html"):
                self._send(200, _render_index(workspace))
                return
            if path.startswith("/entry/"):
                rest = path[len("/entry/"):]
                if rest.endswith("/raw"):
                    eid = rest[:-len("/raw")]
                    safe = _safe_id(eid)
                    if not safe:
                        self._send(400, b"bad id")
                        return
                    entry, _ = _find_entry(workspace, safe)
                    if entry is None:
                        self._send(404, b"not found")
                        return
                    self._send(200,
                               json.dumps(entry, indent=2).encode("utf-8"),
                               ctype="application/json")
                    return
                eid = rest.rstrip("/")
                safe = _safe_id(eid)
                if not safe:
                    self._send(400, b"bad id")
                    return
                code, body = _render_entry(workspace, safe)
                self._send(code, body)
                return
            self._send(404, b"<h1>404</h1>")

        def do_POST(self):  # noqa: N802
            path = urllib.parse.urlparse(self.path).path
            if not path.startswith("/entry/") or not path.endswith("/decide"):
                self._send(404, b"<h1>404</h1>")
                return
            eid = path[len("/entry/"):-len("/decide")]
            safe = _safe_id(eid)
            if not safe:
                self._send(400, b"bad id")
                return
            length = int(self.headers.get("Content-Length") or "0")
            raw = self.rfile.read(length).decode("utf-8")
            form = urllib.parse.parse_qs(raw)
            decision = (form.get("decision") or [""])[0]
            reviewer = (form.get("reviewer") or ["cli"])[0]
            comment = (form.get("comment") or [""])[0]
            if decision not in ("approve", "reject", "needs_changes"):
                self._send(400, b"bad decision")
                return
            rc, output = _decide(ctx, helper, safe, decision,
                                 reviewer, comment)
            if rc != 0:
                msg = ("<h1>decide failed (exit "
                       f"{rc})</h1><pre>{html.escape(output)}</pre>")
                self._send(500, msg.encode("utf-8"))
                return
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()

    return Handler


def run(ctx: CodenookContext, args: Sequence[str], helper: Path) -> int:
    if args and args[0] in ("-h", "--help"):
        print(HELP)
        return 0

    port = 8765
    bind = "127.0.0.1"
    it = iter(args)
    for tok in it:
        if tok == "--port":
            v = next(it, None)
            if v is None:
                sys.stderr.write("hitl serve: --port needs a value\n")
                return 2
            try:
                port = int(v)
            except ValueError:
                sys.stderr.write(f"hitl serve: bad --port: {v}\n")
                return 2
        elif tok == "--bind":
            v = next(it, None)
            if v is None:
                sys.stderr.write("hitl serve: --bind needs a value\n")
                return 2
            bind = v
        else:
            sys.stderr.write(f"hitl serve: unknown arg: {tok}\n")
            return 2

    Handler = _make_handler(ctx, helper)

    class _ReusableTCPServer(socketserver.TCPServer):
        allow_reuse_address = True

    with _ReusableTCPServer((bind, port), Handler) as httpd:
        sys.stderr.write(
            f"codenook hitl serve: listening on http://{bind}:{port}/ "
            f"(workspace={ctx.workspace})\n"
            f"  Ctrl-C to stop. (no auth, no TLS — bind to 127.0.0.1)\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            sys.stderr.write("\ncodenook hitl serve: shutting down\n")
    return 0

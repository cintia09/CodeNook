"""Regression tests for v0.27.17 fixpack.

Covers:
  * S1 — ``codenook chain link --child`` path-traversal rejection
  * S2 — ``codenook task new --id`` path-traversal rejection
  * R1 — ``codenook tick`` envelope augmentation tolerates a
         corrupt state.json without crashing
  * C6 — ``codenook hitl notify`` skips entries that already have
         a ``decision`` field written (decide × scan race)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[4]
INSTALL_PY = REPO_ROOT / "install.py"


def _run(cmd: list[str], cwd: Path | None = None,
         env: dict | None = None) -> subprocess.CompletedProcess:
    e = os.environ.copy()
    e["PYTHONUTF8"] = "1"
    e["PYTHONIOENCODING"] = "utf-8"
    if env:
        e.update(env)
    return subprocess.run(cmd, cwd=str(cwd) if cwd else None,
                          env=e, text=True, capture_output=True,
                          encoding="utf-8", errors="replace")


@pytest.fixture(scope="module")
def ws(tmp_path_factory) -> Path:
    d = tmp_path_factory.mktemp("cn_v17_2")
    cp = _run([sys.executable, str(INSTALL_PY), "--target", str(d), "--yes"])
    assert cp.returncode == 0, cp.stderr
    return d


def _bin(ws: Path) -> list[str]:
    if sys.platform == "win32":
        return [str(ws / ".codenook" / "bin" / "codenook.cmd")]
    return [sys.executable, str(ws / ".codenook" / "bin" / "codenook")]


# ---------------------------------------------------------------- S1

@pytest.mark.parametrize("bad_child", [
    "../../etc/passwd",
    "../escape",
    "/abs/path",
    "..",
    ".hidden",
    "_archived",
    "with/slash",
])
def test_chain_link_rejects_path_traversal_child(ws: Path, bad_child: str) -> None:
    cp = _run(_bin(ws) + [
        "chain", "link", "--child", bad_child, "--parent", "T-001",
    ])
    assert cp.returncode == 2, (cp.stdout, cp.stderr)
    assert "path traversal" in cp.stderr or "invalid --child" in cp.stderr


@pytest.mark.parametrize("bad_parent", [
    "../../etc",
    "/abs",
    "..",
    "a/b",
])
def test_chain_link_rejects_path_traversal_parent(ws: Path, bad_parent: str) -> None:
    cp = _run(_bin(ws) + [
        "chain", "link", "--child", "T-001", "--parent", bad_parent,
    ])
    assert cp.returncode == 2, (cp.stdout, cp.stderr)
    assert "path traversal" in cp.stderr or "invalid --parent" in cp.stderr


# ---------------------------------------------------------------- S2

@pytest.mark.parametrize("bad_id", [
    "../../malicious",
    "../escape",
    "/abs/path",
    "..",
    ".",
    ".hidden",
    "_archive",
    "with/slash",
    "with\\backslash",
])
def test_task_new_rejects_path_traversal_id(ws: Path, bad_id: str) -> None:
    cp = _run(_bin(ws) + [
        "task", "new",
        "--title", "exploit", "--id", bad_id, "--accept-defaults",
    ])
    assert cp.returncode == 2, (cp.stdout, cp.stderr)
    assert "path traversal" in cp.stderr or "invalid --id" in cp.stderr
    # And confirm no directory was created outside the tasks/ sandbox.
    assert not (ws / "malicious").exists()
    assert not (ws / ".codenook" / "malicious").exists()


# ---------------------------------------------------------------- R1

def test_tick_tolerates_corrupt_state_json(ws: Path, tmp_path) -> None:
    """cmd_tick._augment_envelope must not crash on a corrupt state.json.

    We don't run a full tick here (that requires a plugin + real phase
    orchestration). Instead we import the helper directly and confirm
    it returns the tick_out unchanged when state.json is malformed.
    """
    kernel = ws / ".codenook" / "codenook-core"
    cp = _run([sys.executable, "-c", f"""
import sys
sys.path.insert(0, {str(kernel)!r})
sys.path.insert(0, {str(kernel / 'skills' / 'builtin' / '_lib')!r})
from _lib.cli.cmd_tick import _augment_envelope
from _lib.cli.config import CodenookContext
from pathlib import Path

ws = Path({str(ws)!r})
task_dir = ws / '.codenook' / 'tasks' / 'T-999-corrupt-fixture'
task_dir.mkdir(parents=True, exist_ok=True)
(task_dir / 'state.json').write_text('{{{{not json at all', encoding='utf-8')

ctx = CodenookContext(
    workspace=ws,
    state={{}},
    state_file=ws / '.codenook' / 'state.json',
    kernel_dir=ws / '.codenook' / 'codenook-core',
)
result = _augment_envelope(
    ctx, 'T-999-corrupt-fixture',
    '{{\"summary\":\"x\"}}',
)
print(result)
"""])
    assert cp.returncode == 0, cp.stderr
    assert "summary" in cp.stdout


# ---------------------------------------------------------------- C6

def test_hitl_notify_skips_decided_entries(ws: Path, tmp_path) -> None:
    """A queue entry with ``decision`` set must not trigger a webhook POST."""
    qdir = ws / ".codenook" / "hitl-queue"
    qdir.mkdir(parents=True, exist_ok=True)
    # Seed one pending and one already-decided entry.
    (qdir / "T-001-pending_gate.json").write_text(json.dumps({
        "id": "T-001-pending_gate",
        "task_id": "T-001",
        "gate": "pending_gate",
    }), encoding="utf-8")
    (qdir / "T-001-decided_gate.json").write_text(json.dumps({
        "id": "T-001-decided_gate",
        "task_id": "T-001",
        "gate": "decided_gate",
        "decision": "approve",
        "decided_at": "2024-01-01T00:00:00Z",
    }), encoding="utf-8")

    # Run a tiny fake webhook server in-process that records POSTs.
    import http.server
    import socketserver
    import threading

    posted: list[dict] = []

    class H(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n).decode("utf-8")
            try:
                posted.append(json.loads(body))
            except Exception:
                posted.append({"raw": body})
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, *a, **k):
            pass

    srv = socketserver.TCPServer(("127.0.0.1", 0), H)
    port = srv.server_address[1]
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    try:
        cp = _run(_bin(ws) + [
            "hitl", "notify",
            "--webhook", f"http://127.0.0.1:{port}/hook",
            "--once",
        ])
        assert cp.returncode == 0, cp.stderr
    finally:
        srv.shutdown()
        # Clean up seeded fixtures so other tests in the module
        # aren't polluted.
        for f in qdir.glob("T-001-*_gate.json"):
            f.unlink(missing_ok=True)

    # Exactly one POST — for the pending entry. The decided one is skipped.
    assert len(posted) == 1, posted
    assert posted[0]["entry"]["id"] == "T-001-pending_gate"


# ---------------------------------------------------------------- C3

def test_task_new_retry_cap_message_mentions_128(ws: Path) -> None:
    """Sanity: the retry-exhaustion message advertises the new 128 cap
    (no easy way to actually trigger 128 concurrent writers in a test,
    but we can at least pin the user-visible string)."""
    src = (ws / ".codenook" / "codenook-core" / "_lib" / "cli" /
           "cmd_task.py").read_text(encoding="utf-8")
    assert "128 attempts" in src
    assert "16 attempts" not in src

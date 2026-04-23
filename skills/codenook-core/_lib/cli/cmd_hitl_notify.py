"""``codenook hitl notify`` — webhook fan-out for new HITL queue entries.

Polls ``.codenook/hitl-queue/`` and POSTs a JSON envelope to a
configured webhook URL each time a new ``*.json`` file appears (i.e.
a new HITL gate is queued for a human reviewer).

Designed for Slack-incoming-webhook / Discord-webhook / generic JSON
endpoints. The envelope mirrors the queue entry verbatim plus a
top-level ``event`` discriminator.

Modes:
* ``--once``        scan once + exit (handy for cron / CI smoke).
* ``--interval N``  poll every N seconds (default 5).
* ``--header K=V``  extra HTTP header (repeatable).

State is tracked in-memory per process — restart fan-out re-emits
every currently-pending entry. For at-least-once durability across
restarts use the ``--state-file <path>`` flag, which persists the
set of already-notified entry ids to disk.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Sequence

from .config import CodenookContext


HELP = """\
Usage: codenook hitl notify --webhook <url> [--once]
                            [--interval N] [--header K=V]
                            [--state-file <path>] [--user-agent <s>]

Polls .codenook/hitl-queue/ and POSTs a JSON envelope to <url> each
time a new entry appears. Envelope shape:

  {
    "event": "hitl.queued",
    "workspace": "/abs/path",
    "entry": { …raw queue JSON… }
  }

Flags:
  --webhook <url>     required; HTTPS endpoint accepting JSON POST
  --once              scan once and exit (default: loop forever)
  --interval N        seconds between polls in loop mode (default 5)
  --header K=V        extra HTTP header (repeatable, e.g.
                      --header "Authorization=Bearer …")
  --state-file <p>    persist the set of already-notified ids to <p>
                      across restarts (default: in-memory only)
  --user-agent <s>    override the User-Agent header

Exit codes:
  0  loop terminated cleanly (Ctrl-C) or --once succeeded
  1  webhook POST failed and we're in --once mode
  2  usage error
"""


def _queue_dir(ctx: CodenookContext) -> Path:
    return ctx.workspace / ".codenook" / "hitl-queue"


def _scan_pending(ctx: CodenookContext) -> dict[str, dict]:
    """Map entry_id (filename stem) → parsed JSON for every pending entry."""
    out: dict[str, dict] = {}
    qdir = _queue_dir(ctx)
    if not qdir.is_dir():
        return out
    for jf in sorted(qdir.glob("*.json")):
        try:
            data = json.loads(jf.read_text(encoding="utf-8"))
        except Exception:
            continue
        if isinstance(data, dict):
            out[jf.stem] = data
    return out


def _load_state(state_file: Path | None) -> set[str]:
    if state_file is None or not state_file.is_file():
        return set()
    try:
        data = json.loads(state_file.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("notified"), list):
            return set(str(x) for x in data["notified"])
    except Exception:
        pass
    return set()


def _save_state(state_file: Path | None, notified: set[str]) -> None:
    if state_file is None:
        return
    try:
        state_file.parent.mkdir(parents=True, exist_ok=True)
        state_file.write_text(
            json.dumps({"notified": sorted(notified)}, indent=2),
            encoding="utf-8",
        )
    except OSError:
        pass


def _post(url: str, body: dict, headers: dict[str, str],
          ua: str, timeout: float = 10.0) -> tuple[bool, str]:
    payload = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("User-Agent", ua)
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return True, f"HTTP {resp.status}"
    except urllib.error.HTTPError as exc:
        return False, f"HTTP {exc.code}: {exc.reason}"
    except urllib.error.URLError as exc:
        return False, f"URLError: {exc.reason}"
    except Exception as exc:  # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"


def run(ctx: CodenookContext, argv: Sequence[str]) -> int:
    if argv and argv[0] in ("-h", "--help"):
        print(HELP)
        return 0

    webhook: str | None = None
    once = False
    interval = 5.0
    headers: dict[str, str] = {}
    state_file: Path | None = None
    ua = "codenook-hitl-notify/1"

    it = iter(argv)
    for tok in it:
        if tok == "--webhook":
            webhook = next(it, None)
        elif tok == "--once":
            once = True
        elif tok == "--interval":
            v = next(it, None)
            if v is None:
                sys.stderr.write("hitl notify: --interval needs a value\n")
                return 2
            try:
                interval = float(v)
            except ValueError:
                sys.stderr.write(f"hitl notify: bad --interval: {v}\n")
                return 2
        elif tok == "--header":
            kv = next(it, None) or ""
            if "=" not in kv:
                sys.stderr.write(
                    f"hitl notify: --header expects K=V, got: {kv!r}\n")
                return 2
            k, _, v = kv.partition("=")
            headers[k.strip()] = v.strip()
        elif tok == "--state-file":
            sp = next(it, None)
            if not sp:
                sys.stderr.write("hitl notify: --state-file needs a path\n")
                return 2
            state_file = Path(sp).expanduser().resolve()
        elif tok == "--user-agent":
            v = next(it, None)
            if not v:
                sys.stderr.write("hitl notify: --user-agent needs a value\n")
                return 2
            ua = v
        else:
            sys.stderr.write(f"hitl notify: unknown arg: {tok}\n")
            return 2

    if not webhook:
        sys.stderr.write("hitl notify: --webhook <url> is required\n")
        return 2

    notified = _load_state(state_file)

    def _scan_and_post() -> bool:
        """Returns True if every POST in this scan succeeded (or was a no-op)."""
        all_ok = True
        pending = _scan_pending(ctx)
        # Skip entries that were decided in-place (the decide flow
        # writes a `decision` field before moving to _consumed/, so
        # there's a window where the file is still in the queue but
        # no longer pending HITL). Preserves the "notify once per
        # queued entry" contract against decide × scan races.
        pending = {
            eid: data for eid, data in pending.items()
            if not (isinstance(data, dict) and data.get("decision"))
        }
        new_ids = sorted(set(pending) - notified)
        for eid in new_ids:
            envelope = {
                "event": "hitl.queued",
                "workspace": str(ctx.workspace),
                "entry": pending[eid],
            }
            ok, info = _post(webhook, envelope, headers, ua)
            sys.stderr.write(
                f"  hitl-notify: {eid}: {'OK' if ok else 'FAIL'} ({info})\n")
            if ok:
                notified.add(eid)
            else:
                all_ok = False
        # Drop ids that have left the pending queue (decided / archived)
        # so future re-queues with the same id (rare but possible) still
        # notify.
        stale = notified - set(pending)
        if stale:
            notified.difference_update(stale)
        _save_state(state_file, notified)
        return all_ok

    if once:
        ok = _scan_and_post()
        return 0 if ok else 1

    sys.stderr.write(
        f"codenook hitl notify: polling {_queue_dir(ctx)} every "
        f"{interval}s → {webhook}\n  Ctrl-C to stop.\n")
    try:
        while True:
            _scan_and_post()
            time.sleep(interval)
    except KeyboardInterrupt:
        sys.stderr.write("\ncodenook hitl notify: stopped\n")
    return 0

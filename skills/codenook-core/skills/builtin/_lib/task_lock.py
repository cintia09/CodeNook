"""Per-task fcntl lock for tasks/<tid>/router.lock.

Pinned per docs/v6/architecture-v6.md decision #50 and
docs/v6/router-agent-v6.md §6:

  * exclusive ``fcntl.flock(LOCK_EX | LOCK_NB)`` on
    ``tasks/<tid>/router.lock``
  * stale-lock recovery threshold = 300 seconds
  * lock payload JSON = ``{pid, hostname, started_at, task_id}``
    (schema: skills/builtin/router-agent/schemas/router-lock.json.schema.yaml)
  * lock granularity = per-task (different tasks parallel)

The fcntl call is the atomicity primitive: payload write happens
under the held lock so we do not need atomic.py's temp+rename dance
here (the lock IS the atomicity).

POSIX-only. ``fcntl`` is unavailable on Windows; this module raises
``ImportError`` at import time on non-POSIX platforms.

Stale-recovery policy: silent. We detect a stale lock (dead pid OR
``started_at`` older than ``stale_threshold`` OR unparseable payload),
unlink it, log one line to stderr, and retry the acquire loop.
``LockStale`` is exported but not raised by ``acquire()`` — callers
who want to differentiate can re-derive staleness via ``inspect()``
before calling ``acquire()``.

Reentrancy policy: forbidden. A second ``acquire()`` from the same
process for the same ``task_dir`` raises ``LockTimeout`` immediately
(no flock self-deadlock — POSIX flock is per-process advisory and
would silently allow it, which is worse than failing fast).
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import socket
import sys
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

LOCK_FILENAME = "router.lock"

_TASK_ID_RE = re.compile(r"^T-[A-Z0-9.\-]+$")

# task_dir absolute path -> open file descriptor we are holding
_HELD: dict[str, int] = {}


class LockTimeout(Exception):
    """Raised when the lock cannot be acquired within ``timeout``."""


class LockStale(Exception):
    """Reserved: signal that a stale lock was reclaimed.

    Currently never raised — stale recovery is silent (logged to
    stderr). Kept in the public API per the M8.4 spec so future
    callers can opt into a noisier policy without an API break.
    """


# ------------------------------------------------------------- internals


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_iso(s: str) -> float:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s).timestamp()


def _validate_task_dir(task_dir: Path) -> str:
    name = Path(task_dir).name
    if not _TASK_ID_RE.match(name):
        raise ValueError(
            f"task_dir name {name!r} does not match ^T-[A-Z0-9.-]+$"
        )
    return name


def _pid_alive(pid: int) -> bool:
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # signalling forbidden -> process exists, owned by another uid
        return True
    except OSError:
        return False
    return True


def _read_payload(lock_path: Path) -> dict | None:
    try:
        with open(lock_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _is_stale(payload: dict | None, stale_threshold: float) -> bool:
    if not isinstance(payload, dict):
        return True
    pid = payload.get("pid")
    if not isinstance(pid, int) or not _pid_alive(pid):
        return True
    sa = payload.get("started_at")
    if not isinstance(sa, str) or not sa:
        return True
    try:
        age = time.time() - _parse_iso(sa)
    except Exception:
        return True
    return age > stale_threshold


def _write_payload(fd: int, payload: dict) -> None:
    blob = (json.dumps(payload) + "\n").encode("utf-8")
    os.ftruncate(fd, 0)
    os.lseek(fd, 0, 0)
    os.write(fd, blob)
    os.fsync(fd)


# ------------------------------------------------------------- API


@contextmanager
def acquire(
    task_dir: Path,
    *,
    timeout: float = 30.0,
    stale_threshold: float = 300.0,
    poll_interval: float = 0.1,
) -> Iterator[dict]:
    """Acquire the per-task fcntl lock. See module docstring."""
    task_dir = Path(task_dir)
    task_id = _validate_task_dir(task_dir)
    task_dir.mkdir(parents=True, exist_ok=True)
    abs_dir = str(task_dir.resolve())

    if abs_dir in _HELD:
        raise LockTimeout(
            f"router.lock for {task_id} already held by this process "
            "(reentrant acquire is forbidden)"
        )

    lock_path = task_dir / LOCK_FILENAME
    deadline = time.monotonic() + timeout

    while True:
        fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o644)
        got_lock = False
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                got_lock = True
            except BlockingIOError:
                pass

            if got_lock:
                # Guard against the unlink+recreate race: another
                # process may have force-released this file between
                # our os.open and our flock. Re-stat to confirm we
                # hold the *current* lockfile.
                try:
                    st_fd = os.fstat(fd)
                    st_path = os.stat(lock_path)
                except FileNotFoundError:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                    os.close(fd)
                    continue
                if st_fd.st_ino != st_path.st_ino:
                    fcntl.flock(fd, fcntl.LOCK_UN)
                    os.close(fd)
                    continue

                payload = {
                    "pid": os.getpid(),
                    "hostname": socket.gethostname(),
                    "started_at": _now_iso(),
                    "task_id": task_id,
                }
                _write_payload(fd, payload)
                _HELD[abs_dir] = fd
                break  # leave the inner try; yield outside the loop

            # Did not get the lock -> peek payload, maybe stale
            payload = _read_payload(lock_path)
            if _is_stale(payload, stale_threshold):
                try:
                    os.unlink(lock_path)
                    sys.stderr.write(
                        f"task_lock: stale lock for {task_id} cleared "
                        f"(payload={payload!r})\n"
                    )
                except FileNotFoundError:
                    pass
                os.close(fd)
                continue

            os.close(fd)
            if time.monotonic() >= deadline:
                raise LockTimeout(
                    f"could not acquire router.lock for {task_id} "
                    f"within {timeout}s"
                )
            time.sleep(poll_interval)
        except BaseException:
            try:
                if got_lock:
                    fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                try:
                    os.close(fd)
                except OSError:
                    pass
            raise

    try:
        yield payload
    finally:
        try:
            try:
                os.unlink(lock_path)
            except FileNotFoundError:
                pass
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            try:
                os.close(fd)
            except OSError:
                pass
            _HELD.pop(abs_dir, None)


def inspect(task_dir: Path) -> dict | None:
    """Return current lock payload, or None if absent / unparseable."""
    lock_path = Path(task_dir) / LOCK_FILENAME
    if not lock_path.exists():
        return None
    return _read_payload(lock_path)


def force_release(task_dir: Path) -> bool:
    """Forcibly delete the lockfile. For ops/recovery only."""
    lock_path = Path(task_dir) / LOCK_FILENAME
    try:
        os.unlink(lock_path)
        return True
    except FileNotFoundError:
        return False


__all__ = [
    "LockTimeout",
    "LockStale",
    "LOCK_FILENAME",
    "acquire",
    "inspect",
    "force_release",
]

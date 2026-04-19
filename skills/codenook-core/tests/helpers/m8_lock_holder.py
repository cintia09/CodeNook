#!/usr/bin/env python3
"""Hold a task_lock for a fixed duration.

Used by m8-task-lock*.bats. The harness needs an out-of-process
holder so the second acquirer can race against a real other PID
(in-process holders would short-circuit the reentrancy guard).

Usage:
    LIB_DIR=<...path...> python3 m8_lock_holder.py <task_dir> <hold_seconds>

On stdout (line 1, flushed): the holder PID (so the parent test
can wait until the lock is definitely held before racing).
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

lib_dir = os.environ.get("LIB_DIR")
if not lib_dir:
    print("LIB_DIR env var required", file=sys.stderr)
    sys.exit(2)
sys.path.insert(0, lib_dir)

import task_lock  # noqa: E402

if len(sys.argv) != 3:
    print("usage: m8_lock_holder.py <task_dir> <hold_seconds>", file=sys.stderr)
    sys.exit(2)

task_dir = Path(sys.argv[1])
hold = float(sys.argv[2])

with task_lock.acquire(task_dir, timeout=5.0) as payload:
    print(payload["pid"], flush=True)
    time.sleep(hold)

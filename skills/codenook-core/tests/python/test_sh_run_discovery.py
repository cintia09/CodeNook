"""Tests for v0.23.1 Windows bash auto-discovery in sh_run.find_bash()."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# conftest.py already adds _lib to sys.path, but be defensive.
_LIB = Path(__file__).resolve().parents[3] / "skills" / "builtin" / "_lib"
if str(_LIB) not in sys.path:
    sys.path.insert(0, str(_LIB))

import sh_run  # noqa: E402


@pytest.fixture(autouse=True)
def _reset_cache():
    sh_run._reset_cache_for_tests()
    yield
    sh_run._reset_cache_for_tests()


def _make_fake_bash(tmp_path: Path, name: str = "bash.exe") -> Path:
    p = tmp_path / name
    p.write_text("#!/bin/sh\nexit 0\n")
    return p


def test_cn_bash_env_honored(tmp_path, monkeypatch):
    fake = _make_fake_bash(tmp_path)
    monkeypatch.setenv("CN_BASH", str(fake))
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    assert sh_run.find_bash() == str(fake)


def test_cn_bash_nonexistent_falls_through(tmp_path, monkeypatch):
    monkeypatch.setenv("CN_BASH", str(tmp_path / "does-not-exist.exe"))
    sentinel = "/usr/bin/bash-from-which"
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: sentinel)
    assert sh_run.find_bash() == sentinel


def test_well_known_scan_triggers_when_path_empty(tmp_path, monkeypatch):
    fake = _make_fake_bash(tmp_path)
    monkeypatch.delenv("CN_BASH", raising=False)
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_PATHS", (str(fake),))
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_GLOBS", ())
    monkeypatch.setattr(sh_run.os, "name", "nt")
    assert sh_run.find_bash() == str(fake)


def test_well_known_glob_scan(tmp_path, monkeypatch):
    user_dir = tmp_path / "alice" / "AppData" / "Local" / "Programs" / "Git" / "bin"
    user_dir.mkdir(parents=True)
    fake = _make_fake_bash(user_dir)
    monkeypatch.delenv("CN_BASH", raising=False)
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_PATHS", ())
    pattern = str(tmp_path / "*" / "AppData" / "Local" / "Programs" / "Git" / "bin" / "bash.exe")
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_GLOBS", (pattern,))
    monkeypatch.setattr(sh_run.os, "name", "nt")
    assert sh_run.find_bash() == str(fake)


def test_returns_none_when_all_fail(monkeypatch):
    monkeypatch.delenv("CN_BASH", raising=False)
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_PATHS", ())
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_GLOBS", ())
    monkeypatch.setattr(sh_run.os, "name", "nt")
    assert sh_run.find_bash() is None


def test_cache_avoids_rescan(tmp_path, monkeypatch):
    fake = _make_fake_bash(tmp_path)
    monkeypatch.setenv("CN_BASH", str(fake))
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    assert sh_run.find_bash() == str(fake)

    calls = {"n": 0}

    def _spy(_):
        calls["n"] += 1
        return None

    monkeypatch.setattr(sh_run.shutil, "which", _spy)
    monkeypatch.delenv("CN_BASH", raising=False)
    # Cached result is returned without re-scanning shutil.which.
    assert sh_run.find_bash() == str(fake)
    assert calls["n"] == 0


def test_sh_run_passthrough_on_posix(monkeypatch):
    """On non-Windows, sh_run delegates straight to subprocess.run without
    any bash injection."""
    monkeypatch.setattr(sh_run.os, "name", "posix")
    captured = {}

    def _fake_run(cmd, **kwargs):
        captured["cmd"] = cmd
        captured["kwargs"] = kwargs

        class _R:
            returncode = 0
        return _R()

    monkeypatch.setattr(sh_run.subprocess, "run", _fake_run)
    sh_run.sh_run(["foo.sh", "--bar"], check=False)
    assert captured["cmd"] == ["foo.sh", "--bar"]


def test_sh_run_raises_clear_error_when_bash_missing(monkeypatch):
    monkeypatch.setattr(sh_run.os, "name", "nt")
    monkeypatch.delenv("CN_BASH", raising=False)
    monkeypatch.setattr(sh_run.shutil, "which", lambda _: None)
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_PATHS", ())
    monkeypatch.setattr(sh_run, "_WELL_KNOWN_GLOBS", ())
    with pytest.raises(RuntimeError, match="no bash interpreter"):
        sh_run.sh_run(["foo.sh"])

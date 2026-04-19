"""LLM call wrapper (M9.3).

A thin adapter that lets the extractor / decision flow stay decoupled from
any specific provider. Three modes:

    mock (default)  — deterministic responses, used by every bats test.
    real            — shell out to ``claude --print --no-stream``.

Mock resolution order (first match wins):

    1. ``$CN_LLM_MOCK_DIR/<call_name>.json`` or ``.txt`` (file content).
    2. ``$CN_LLM_MOCK_<CALL_NAME_UPPER>``                (env var content).
    3. ``$CN_LLM_MOCK_RESPONSE``                         (env var content).
    4. ``$CN_LLM_MOCK_FILE``                             (file path).
    5. Fallback: ``"[mock-llm:<call_name>] " + prompt[:80]``.

Error injection (raised before mock resolution):

    ``$CN_LLM_MOCK_ERROR_<CALL_NAME_UPPER>``  → ``RuntimeError(value)``
    ``$CN_LLM_MOCK_ERROR``                    → ``RuntimeError(value)``

The mock contract is the test-input side of the M9.0.1 §0.3 protocol; in
real mode the wrapper shells out to the Claude CLI.

Public API::

    call_llm(prompt, *, call_name="default", system=None, max_tokens=2048,
             mode=None, timeout=30.0) -> str
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

DEFAULT_TIMEOUT = 30.0


def _normalize_call_name(call_name: str) -> str:
    return call_name.upper().replace("-", "_")


def _resolve_mode(mode: str | None) -> str:
    if mode:
        return mode.lower()
    return os.environ.get("CN_LLM_MODE", "mock").lower()


def _maybe_raise_injected(call_name: str) -> None:
    name_upper = _normalize_call_name(call_name)
    err_specific = os.environ.get(f"CN_LLM_MOCK_ERROR_{name_upper}")
    if err_specific:
        raise RuntimeError(err_specific)
    err_generic = os.environ.get("CN_LLM_MOCK_ERROR")
    if err_generic:
        raise RuntimeError(err_generic)


def _mock_response(prompt: str, call_name: str) -> str:
    _maybe_raise_injected(call_name)

    name_upper = _normalize_call_name(call_name)
    mock_dir = os.environ.get("CN_LLM_MOCK_DIR")
    if mock_dir:
        for ext in (".json", ".txt"):
            p = Path(mock_dir) / f"{call_name}{ext}"
            if p.is_file():
                return p.read_text(encoding="utf-8")

    env_specific = os.environ.get(f"CN_LLM_MOCK_{name_upper}")
    if env_specific is not None:
        return env_specific

    env_resp = os.environ.get("CN_LLM_MOCK_RESPONSE")
    if env_resp is not None:
        return env_resp

    env_file = os.environ.get("CN_LLM_MOCK_FILE")
    if env_file:
        return Path(env_file).read_text(encoding="utf-8")

    return f"[mock-llm:{call_name}] {prompt[:80]}"


def _real_response(prompt: str, system: str | None, timeout: float) -> str:
    cmd = ["claude", "--print", "--no-stream"]
    if system:
        cmd += ["--append-system-prompt", system]
    try:
        proc = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except FileNotFoundError as e:
        raise RuntimeError(f"claude CLI not found: {e}") from e
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"claude CLI timeout after {timeout}s") from e
    if proc.returncode != 0:
        raise RuntimeError(
            f"claude CLI exited {proc.returncode}: {proc.stderr.strip()}"
        )
    return proc.stdout


def call_llm(
    prompt: str,
    *,
    call_name: str = "default",
    system: str | None = None,
    max_tokens: int = 2048,  # noqa: ARG001 — provider-specific, reserved.
    mode: str | None = None,
    timeout: float = DEFAULT_TIMEOUT,
) -> str:
    """Invoke the LLM and return the raw text response.

    Raises:
        TypeError:    if ``prompt`` isn't a string.
        ValueError:   if ``mode`` resolves to something other than mock/real.
        RuntimeError: on injected mock error or real-mode failure.
    """
    if not isinstance(prompt, str):
        raise TypeError("prompt must be str")

    resolved = _resolve_mode(mode)
    if resolved == "mock":
        return _mock_response(prompt, call_name)
    if resolved == "real":
        return _real_response(prompt, system, timeout)
    raise ValueError(f"unknown llm mode: {resolved!r}")

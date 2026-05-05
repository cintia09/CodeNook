from __future__ import annotations

import subprocess
import sys
import textwrap
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
POST_TEST_PLAN = REPO_ROOT / "plugins" / "development" / "validators" / "post-test-plan.py"


def _write_test_plan(tmp_path: Path, body: str) -> None:
    out = tmp_path / ".codenook" / "tasks" / "T-001" / "outputs" / "phase-8-test-planner.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(textwrap.dedent(body).lstrip(), encoding="utf-8")


def _run_post_test_plan(tmp_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(POST_TEST_PLAN), "T-001"],
        cwd=tmp_path,
        text=True,
        capture_output=True,
        encoding="utf-8",
        errors="replace",
    )


def test_post_test_plan_requires_real_e2e_choice(tmp_path: Path) -> None:
    _write_test_plan(
        tmp_path,
        """
        ---
        verdict: ok
        summary: local plan
        case_count: 1
        runner: pytest
        environment: local-python
        environment_source: user-asked
        submitted_ref: abc123
        ---

        ## Submitted Ref
        abc123

        ## Test Cases
        TC-1.
        """,
    )

    cp = _run_post_test_plan(tmp_path)

    assert cp.returncode == 1
    assert "real_e2e_required" in cp.stderr


def test_post_test_plan_rejects_local_env_when_real_e2e_required(tmp_path: Path) -> None:
    _write_test_plan(
        tmp_path,
        """
        ---
        verdict: ok
        summary: real e2e requested
        case_count: 1
        runner: npm
        real_e2e_required: yes
        environment: local-node
        environment_source: user-asked
        submitted_ref: abc123
        ---

        ## Submitted Ref
        abc123

        ## Test Cases
        TC-1.
        """,
    )

    cp = _run_post_test_plan(tmp_path)

    assert cp.returncode == 1
    assert "cannot use local-node" in cp.stderr


def test_post_test_plan_allows_local_env_when_real_e2e_not_required(tmp_path: Path) -> None:
    _write_test_plan(
        tmp_path,
        """
        ---
        verdict: ok
        summary: local plan accepted
        case_count: 1
        runner: pytest
        real_e2e_required: no
        environment: local-python
        environment_source: user-asked
        submitted_ref: abc123
        ---

        ## Submitted Ref
        abc123

        ## Test Cases
        TC-1.
        """,
    )

    cp = _run_post_test_plan(tmp_path)

    assert cp.returncode == 0, cp.stderr

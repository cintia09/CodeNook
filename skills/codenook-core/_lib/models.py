"""v0.18 — LLM model resolution chain.

Resolves which model the conductor should pass to its sub-agent task
tool when dispatching a phase agent. Priority (first hit wins):

  C — Task override   .codenook/tasks/<T-NNN>/state.json :: model_override
  B — Phase default   .codenook/plugins/<id>/phases.yaml :: phases[*].model
  A — Plugin default  .codenook/plugins/<id>/plugin.yaml :: default_model
  D — Workspace       .codenook/config.yaml              :: default_model

Returns ``None`` when nothing is set anywhere — callers (cmd_tick) MUST
omit the ``model`` key from the dispatch envelope entirely in that case
so the conductor falls back to its platform default. The model string
is opaque; this helper does not validate it.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

try:
    import yaml  # type: ignore[import-untyped]
except Exception:  # pragma: no cover — pyyaml is a hard dep elsewhere
    yaml = None  # type: ignore[assignment]


def _safe_yaml(path: Path) -> dict:
    if yaml is None or not path.is_file():
        return {}
    try:
        doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        return doc if isinstance(doc, dict) else {}
    except Exception:
        return {}


def _phase_model(phases_yaml: Path, phase_id: str) -> Optional[str]:
    doc = _safe_yaml(phases_yaml)
    raw = doc.get("phases")
    if isinstance(raw, dict):
        entry = raw.get(phase_id)
        if isinstance(entry, dict):
            v = entry.get("model")
            return v if isinstance(v, str) and v else None
        return None
    if isinstance(raw, list):
        for entry in raw:
            if isinstance(entry, dict) and entry.get("id") == phase_id:
                v = entry.get("model")
                return v if isinstance(v, str) and v else None
    return None


def resolve_model(
    workspace: Path,
    plugin_id: str,
    phase_id: str,
    task_state: dict,
) -> Optional[str]:
    """Return the resolved model string per the C>B>A>D chain, or None."""
    # C — task override
    override = task_state.get("model_override") if isinstance(task_state, dict) else None
    if isinstance(override, str) and override:
        return override

    plugin_dir = workspace / ".codenook" / "plugins" / plugin_id

    # B — phase default
    if plugin_id and phase_id:
        v = _phase_model(plugin_dir / "phases.yaml", phase_id)
        if v:
            return v

    # A — plugin default
    if plugin_id:
        plugin_doc = _safe_yaml(plugin_dir / "plugin.yaml")
        v = plugin_doc.get("default_model")
        if isinstance(v, str) and v:
            return v

    # D — workspace default
    ws_doc = _safe_yaml(workspace / ".codenook" / "config.yaml")
    v = ws_doc.get("default_model")
    if isinstance(v, str) and v:
        return v

    return None

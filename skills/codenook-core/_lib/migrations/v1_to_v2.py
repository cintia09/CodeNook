"""Migration v1 → v2.

Normalises optional-but-conventionally-present fields:

* ``priority`` defaults to ``"P2"`` if missing or empty (the same
  default used by ``task new --accept-defaults``).
* ``history`` is coerced to ``[]`` when absent so downstream code
  can append unconditionally.

Idempotent: re-running on a v2 state is a no-op (the priority/history
fields will already be present, and we always overwrite
``schema_version`` to 2).

Why this is "trivial": it does not introduce any new required field
in the schema — it only fills holes that legacy task creators
sometimes left empty. The real value is establishing the migration
infrastructure so future schema bumps have a tested path.
"""
from __future__ import annotations


def migrate(state: dict) -> dict:
    out = dict(state)
    if not out.get("priority"):
        out["priority"] = "P2"
    if "history" not in out or out["history"] is None:
        out["history"] = []
    out["schema_version"] = 2
    return out

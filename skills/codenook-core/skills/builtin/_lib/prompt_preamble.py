"""Shared preamble injected into every rendered phase prompt.

v0.29.21 — Sub-agents that handle phase work do NOT read the
workspace bootloader (CLAUDE.md / copilot-instructions.md); they
only see their role.md plus the per-phase prompt rendered by the
kernel. The schema-validation errors that v0.29.18 / v0.29.19
tried to head off via the bootloader (`"question": Required`,
`Expected array, received string`) keep recurring because the
sub-agent never sees the bootloader rule.

This module supplies a small, host-agnostic preamble that the
two phase-prompt renderers (orchestrator-tick `_tick.py` and
CLI `cmd_tick.py`) prepend to every rendered prompt. Keep it
short — sub-agent context budgets are tight — and keep it tool-
name-agnostic since hosts vary (Claude Code: `ask_user`;
VS Code Copilot: `vscode_askQuestions`; other hosts: their own
interactive-prompt facility).
"""

INTERACTIVE_TOOL_PREAMBLE = (
    "<!-- codenook:interactive-tool-shape v0.29.21 -->\n"
    "## Interactive-prompt tool — schema reminder\n"
    "\n"
    "If you need to ask the user a question from inside this\n"
    "phase, call your host's interactive-question tool with its\n"
    "NATIVE structured parameters. The tool name varies by host\n"
    "(Claude Code: `ask_user`; VS Code Copilot:\n"
    "`vscode_askQuestions`; other hosts: their own facility).\n"
    "The shape rules below are universal:\n"
    "\n"
    "- The question / prompt field is REQUIRED. Pass the\n"
    "  question text in that field. Do not stuff it inside a\n"
    "  `choices` / `options` / `items` field or into a free-form\n"
    "  blob.\n"
    "- The choices / options field, when used, is a real JSON\n"
    "  array of short strings (e.g. `[\"yes\", \"no\"]`). Never\n"
    "  a stringified array (`\"['yes','no']\"`), never a\n"
    "  newline-joined string.\n"
    "- Booleans stay booleans, numbers stay numbers — keep every\n"
    "  declared type.\n"
    "- Validation-error fingerprints (and the fix):\n"
    "  - `\"question\": Required` / `\"prompt\": Required` →\n"
    "    you forgot the question field, or put the text in the\n"
    "    wrong field. Move it back into the question field.\n"
    "  - `Expected array, received string` on a choices-like\n"
    "    field → pass a real JSON array, not its string repr.\n"
    "- Ask one focused question per call; do not bundle multiple\n"
    "  questions into one prompt.\n"
    "\n"
    "<!-- /codenook:interactive-tool-shape -->\n"
    "\n"
)


def prepend_interactive_preamble(body: str) -> str:
    """Return ``body`` with the interactive-tool preamble prepended.

    Idempotent — if the marker is already present, ``body`` is
    returned unchanged so re-renders don't stack copies.
    """
    if not isinstance(body, str):
        return body
    if "codenook:interactive-tool-shape" in body:
        return body
    return INTERACTIVE_TOOL_PREAMBLE + body

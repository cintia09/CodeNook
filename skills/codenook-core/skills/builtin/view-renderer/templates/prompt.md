# Prompt template — view-renderer

You are rewriting one CodeNook role-output markdown file into two
artefacts a human reviewer will actually read:

1. An HTML body fragment (no `<html>` / `<head>` / `<body>` tags — the
   wrapper template provides those).
2. An ANSI-styled plain-text version for the terminal.

The role output is **structured for the distiller** — it has YAML
front-matter, jargon section names ("Acceptance criteria", "task_type
rationale", "Goal (user vocabulary)"), and reference-style code paths.
The reviewer doesn't care about any of that. Your job is to make the
content scan in five seconds.

## Inputs

- `eid`: `{{eid}}`
- `task_id`: `{{task_id}}`
- `gate`: `{{gate}}`
- `context_path`: `{{context_path}}`
- `context` (raw role markdown):

````markdown
{{context}}
````

## Rules for the HTML body

1. **Always start with one `<h1>` summarising the gate purpose** in the
   reader's voice (e.g. "Confirm the bug fix scope" not "Clarifier —
   T-001"). Keep ≤8 words.
2. **Drop entirely:** YAML front-matter, any `## ... rationale`
   section, any `Self-bootstrap` / `Inputs you MUST read` / `Output
   contract` boilerplate intended for the agent, the trailing
   `Knowledge` / `Skills` paragraphs.
3. **Keep & rephrase:** the goal, the acceptance criteria, the
   non-goals, and any open questions. Use plain reader language for
   section titles. If the source is in Chinese, keep Chinese.
4. **Visualise when it helps.** When the content describes a flow,
   state machine, sequence, or architecture, emit a mermaid block
   above the related text:

   ```html
   <pre class="mermaid">
   flowchart LR
     A[clarifier] --> B[implementer]
     B --> C[reviewer]
   </pre>
   ```

   Mermaid is preloaded via CDN — no extra setup needed. Pick the
   simplest mermaid shape (`flowchart`, `sequenceDiagram`,
   `stateDiagram-v2`, `pie`). Skip the diagram entirely if the content
   is just text.
5. **Code & paths**: render fenced blocks as
   `<pre><code class="language-X">...</code></pre>`. Inline file
   paths and identifiers as `<code>...</code>`.
6. **Links**: keep all URLs as `<a href="..." target="_blank"
   rel="noopener">...</a>`.
7. **Length**: aim for ≤60% of the source's prose volume. Cut
   redundancy ruthlessly.
8. **Do NOT add a footer** — the wrapper template appends a
   `Source: <context_path>` link automatically.

## Rules for the ANSI text

Same content as the HTML body, but in monochrome-friendly markdown
with light ANSI accents:

- Headers as `# ` / `## ` (no styling — the terminal renderer adds
  colour).
- Bullet lists as `- item`.
- Code blocks fenced with triple backticks (no syntax highlighting).
- No mermaid blocks (terminal can't render them) — replace with a
  short prose summary like "Flow: clarifier → implementer → reviewer."
- Trailing `Source: <context_path>` line.

## Output contract

Write the HTML body fragment to **`{{html_out_wrapped_path}}`** (the
host wraps it through `templates/reviewer.html.template` with
`{{title}} = "<task_id> · <gate>"`, `{{body}} = your fragment`,
`{{src_path}} = <context_path>`). Write the ANSI text to
**`{{ansi_out_path}}`**.

Both files are atomic single-shot writes. If you cannot complete the
rewrite, write nothing and exit — `_hitl.py` will fall back to its
stdlib renderer.

---
name: mermaid-render
description: |
  Render Mermaid diagrams (.mmd files, or ```mermaid blocks inside Markdown) into
  a single reviewable HTML page — theme-aware, one card per diagram, with each
  diagram's source file and `%% sources:` traceability line shown. Use when the
  user wants to *look at* diagrams before approving them: design reviews, C4 /
  UML / sequence / state diagrams, architecture walkthroughs, or the `design`
  phase of a dev harness. Also use when asked to "render", "visualize", "preview",
  or "show" Mermaid diagrams, or to turn .mmd files into something viewable.
---

# Mermaid Render

Turns Mermaid sources into one HTML page a human can actually review.

## Usage

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o OUT.html [--title TITLE] [--open] FILE...
```

| Flag | Meaning |
|---|---|
| `-o`, `--out` | Output HTML path (required). Parent dirs are created. |
| `--title` | Page heading. Default: `Diagram Review`. |
| `--open` | Open in the default browser afterwards (Windows/macOS/Linux). |

Inputs:

- `*.mmd` / `*.mermaid` — one diagram per file
- `*.md` — every ` ```mermaid ` fenced block becomes its own diagram

Multiple inputs land on one page in the order given, so a whole iteration's
design can be reviewed in a single scroll.

## Examples

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o docs/uml/review.html --title "C4 Review" docs/uml/*.mmd
```

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o docs/iterations/ITER-01.html --title "ITER-01 Design" --open docs/iterations/ITER-01.md
```

## After rendering

Show the file to the user — do not just report the path. Use `SendUserFile`
with `display: "render"` so the page opens in the side panel, or pass `--open`
to launch their browser. The point of this skill is that a human *looks* at the
diagram before approving it.

## Notes

- The generated HTML is plain, committable, and diffable. It loads Mermaid from
  a CDN, so viewing needs network access on first load; the file itself has no
  build step and no local dependency.
- Diagram text is HTML-escaped losslessly — `-->`, `<<interface>>`, and `&`
  survive the round-trip and reach Mermaid unchanged.
- A diagram that fails to parse renders an inline error on the page instead of
  breaking the other diagrams. If the user reports a red error box, fix the
  `.mmd` source and re-render.
- The page honours the viewer's light/dark preference and has a theme toggle.

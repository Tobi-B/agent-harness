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
bash ~/.claude/skills/mermaid-render/render.sh -o OUT.html [--title TITLE] [--shared-lib|--cdn] [--open] FILE...
```

| Flag | Meaning |
|---|---|
| `-o`, `--out` | Output HTML path (required). Parent dirs are created. |
| `--title` | Page heading. Default: `Diagram Review`. |
| `--shared-lib` | Write `mermaid.min.js` next to the output and link it. |
| `--cdn` | Link the CDN copy instead of embedding. |
| `--open` | Open in the default browser afterwards. |

Inputs:

- `*.mmd` / `*.mermaid` — one diagram per file
- `*.md` — every ` ```mermaid ` fenced block becomes its own diagram

Multiple inputs land on one page in the order given, so a whole iteration's
design can be reviewed in a single scroll.

## Choosing a library mode

**Default (self-contained)** — embeds the vendored Mermaid build in the page.
~3.5 MB, but it renders offline, from `file://`, and inside viewers that block
external hosts. Use this for one-off reviews and anything you send to someone.

**`--shared-lib`** — one `mermaid.min.js` beside many small pages (~7 KB each).
Use this when the pages are committed, e.g. one per harness iteration under
`docs/iterations/`. Keep the library file next to them.

**`--cdn`** — smallest, but renders **nothing** when offline or when external
hosts are blocked. Only for pages served on a network you control.

## Examples

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o docs/uml/review.html --title "C4 Review" docs/uml/*.mmd
```

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o docs/iterations/ITER-01.html \
  --shared-lib --title "ITER-01 Design" docs/iterations/ITER-01.md
```

## After rendering

Show the file to the user — do not just report the path. Use `SendUserFile`
with `display: "render"`, or pass `--open` to launch their browser. The point
of this skill is that a human *looks* at the diagram before approving it.

A `--cdn` page will not render inside sandboxed viewers that block external
hosts; the default self-contained mode does.

## Notes

- **Never switch the page to `mermaid.esm.min.mjs`.** That file is a 29 KB
  loader which pulls dozens of relative chunks at view time; if any request is
  blocked, the page silently shows raw text instead of diagrams. The vendored
  UMD build (`vendor/mermaid.min.js`, v11.16.0) is self-contained and sets
  `globalThis.mermaid`.
- If the library is missing, `render.sh` fetches it once into `vendor/` and
  caches it; if that fails it falls back to `--cdn` with a warning.
- When Mermaid cannot load at all, the page shows an explicit banner and labels
  the sources as text — a silent wall of code would be indistinguishable from
  a broken render.
- Diagram text is HTML-escaped losslessly — `-->`, `<<interface>>`, and `&`
  survive the round-trip and reach Mermaid unchanged.
- A diagram that fails to parse renders an inline error on the page instead of
  breaking the other diagrams.
- The page honours the viewer's light/dark preference and has a theme toggle.

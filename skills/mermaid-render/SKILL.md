---
name: mermaid-render
description: |
  Render Mermaid diagrams (.mmd files, or ```mermaid blocks inside Markdown)
  into something a human can review. Default: publish as an Artifact (native
  Mermaid rendering, shareable URL, works in every client including
  remote-control views). Fallback: render.sh for a committed file or when
  something checks for a local file on disk (e.g. the harness-init design
  gate). Use when the user wants to *look at* diagrams before approving them:
  design reviews, C4 / UML / sequence / state diagrams, architecture
  walkthroughs, or the `design` phase of a dev harness. Also use when asked to
  "render", "visualize", "preview", or "show" Mermaid diagrams, or to turn
  .mmd files into something viewable.
---

# Mermaid Render

Two ways to turn Mermaid sources into something reviewable — pick by what
happens to the output next.

## Default: publish as an Artifact

Use this whenever a human just wants to *look at* the diagram(s) now. It's the
default because it needs no vendored library (Artifacts render `<pre
class="mermaid">` natively), produces a real shareable/updatable URL instead
of a file attachment, and — unlike `SendUserFile` — actually renders in
clients that only show attachments as filenames (e.g. remote-control views).

**Steps:**

1. Read the input(s): `*.mmd` / `*.mermaid` (one diagram, whole file) or
   `*.md` (every ` ```mermaid ` fence becomes one diagram, in source order —
   grab the heading above each fence as its card label if one exists).
2. This template already satisfies the `artifact-design` calibration for a
   diagram-review page (a polished memo, not a landing page) — skip
   re-deriving it. Reload `artifact-design` only if the diagrams are heading
   into something editorial (a landing page, a pitch) instead of a straight
   review page.
3. Write one HTML file using the token system and structure below. Each
   diagram goes in its own `<pre class="mermaid">` block containing the
   **HTML-escaped** raw source — escape `&`, `<`, `>` yourself; you're
   writing literal HTML directly, there's no script doing it for you this
   time.
4. Call `Artifact` with a specific title (`"<Feature> UML"`, not `"Diagram
   Review"`), a one-line `description`, and one short generic `icon` word such
   as `diagram` or `chart` (`favicon` is deprecated). Keep the icon stable
   across re-renders of the same review, and omit it on a redeploy so the
   artifact keeps the one it has.
5. Hand the user the URL directly in your reply. Don't also send the file via
   `SendUserFile` — the artifact URL is the deliverable, a duplicate file
   attachment is noise.

Before publishing anything to a hosted artifact, apply the same judgment as
any other artifact: skip it (or ask first) if the diagram content is
confidential enough that even a private, unlisted URL is unwanted — a local
`render.sh` file never leaves the machine.

### Structure

- Sticky topbar: short source label (left) + one anchor link per diagram
  section (right), so a multi-diagram review is a single scroll with jump
  links.
- Header: eyebrow (context line — phase/slice/doc type, whatever you actually
  have), title (the subject, not "Diagram Review"), and — only if the source
  material gives you real values, never invented — a status pill (e.g. DRAFT)
  and a small metadata grid (mapped requirements, stories, whatever the
  surrounding docs define). Omit any block you don't have real data for.
- One `.diagram-card` per diagram: label, one-sentence caption of what it
  shows (write this yourself from the diagram content — don't skip it), then
  the diagram in a `.diagram-scroll` wrapper (`overflow-x: auto`, centered).
- Optional closing `.notes` section if the source `.md` has prose worth
  surfacing (a "Notes" heading, caveats, open questions).
- Footer: the source file path(s), so the page is traceable back to disk.

### Design tokens

Blueprint-schematic identity — a technical review tool, not a marketing page.
Headings in a monospace face (the content is full of identifiers and class
names; lean into that instead of fighting it with a display serif), body in a
humanist sans, single desaturated cyan accent used only for links, the active
nav state, and the status pill.

```css
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@500;600;700&family=Public+Sans:wght@400;500;600&display=swap');

:root {
  --bg: #f4f6f8;
  --surface: #ffffff;
  --surface-alt: #e9edf1;
  --border: #d7dee5;
  --text: #17222c;
  --text-muted: #57697a;
  --accent: #0f6e8c;
  --accent-strong: #0b5470;
  --status-bg: #fdf1dc;
  --status-text: #8a5a12;
  --status-border: #edd9ab;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --bg: #0d1216; --surface: #141b21; --surface-alt: #1a232a;
    --border: #29343d; --text: #e6edf1; --text-muted: #93a3b0;
    --accent: #4fb8dd; --accent-strong: #7fd0ea;
    --status-bg: #2c2410; --status-text: #e0b45c; --status-border: #493c1c;
  }
}
:root[data-theme="dark"] {
  --bg: #0d1216; --surface: #141b21; --surface-alt: #1a232a;
  --border: #29343d; --text: #e6edf1; --text-muted: #93a3b0;
  --accent: #4fb8dd; --accent-strong: #7fd0ea;
  --status-bg: #2c2410; --status-text: #e0b45c; --status-border: #493c1c;
}
```

- Headings: `"JetBrains Mono", ui-monospace, monospace` — 600/700 weight,
  `text-wrap: balance`.
- Body + labels: `"Public Sans", system-ui, sans-serif`.
- `body` gets an explicit `background: var(--bg)` (never leave it
  transparent — see `artifact-design`'s theme rules for why).
- Diagram cards: `background: var(--surface)`, `border: 1px solid
  var(--border))`, `border-radius: 10px`, subtle shadow.
- Status pill background/text/border come from the `--status-*` tokens, not
  the main accent — semantic state stays visually separate from the accent
  hue.

## Alternative: `render.sh` (needs a real file on disk)

Reach for the script instead of an Artifact when the output must be a file
with a genuine mtime — most notably the `harness-init` skill's `design` gate
(`gates/design.sh`) checks `[ -f docs/iterations/<iter>.html ]` and that it
isn't older than its `.md` source; a hosted Artifact URL can't satisfy a
filesystem check like that. Also use it for a page meant to live in the repo
long-term, or one that must render fully offline from `file://`.

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

Inputs: same as above (`*.mmd`/`*.mermaid` one diagram per file, `*.md` every
fenced block).

**Choosing a library mode:** default (self-contained, ~3.5 MB, works
offline/under strict CSP) for one-off reviews; `--shared-lib` when many pages
share one directory (e.g. `docs/iterations/`); `--cdn` only on a network you
control, since it renders nothing offline.

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o docs/uml/review.html --title "C4 Review" docs/uml/*.mmd
```

After rendering, show the file with `SendUserFile` (`display: "render"`) or
`--open` — this path has no URL to hand back instead.

**Notes:** never switch to `mermaid.esm.min.mjs` (a 29 KB loader that pulls
relative chunks at view time and silently shows raw text if any is blocked —
the vendored UMD build is self-contained). If the vendored library is
missing, the script fetches it once into `vendor/` and caches it, falling
back to `--cdn` with a warning if that fails. A parse failure on one diagram
renders an inline error instead of breaking the rest of the page.

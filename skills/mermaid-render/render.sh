#!/usr/bin/env bash
# Render Mermaid diagrams into one reviewable HTML page.
#
# Usage:
#   render.sh -o OUT.html [--title TITLE] [--open] FILE...
#
# FILE may be:
#   *.mmd / *.mermaid  — one diagram per file
#   *.md               — every ```mermaid fenced block becomes a diagram
#
# The page is theme-aware, prints each diagram's source file and its
# `%% sources:` traceability line, and loads mermaid from a CDN (needs network
# on first view; the generated file itself is plain HTML you can commit).
set -euo pipefail

out=""
title="Diagram Review"
open_after=0
files=()

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)   out="$2"; shift 2 ;;
    --title)    title="$2"; shift 2 ;;
    --open)     open_after=1; shift ;;
    -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown option: $1" >&2; exit 2 ;;
    *)          files+=("$1"); shift ;;
  esac
done

[ -n "$out" ] || { echo "FAIL: -o OUT.html is required" >&2; exit 2; }
[ "${#files[@]}" -gt 0 ] || { echo "FAIL: no input files" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Emits: <label>\t<path-to-diagram-body> per line, into $WORK/index
: > "$WORK/index"
n=0

for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "FAIL: no such file: $f" >&2; exit 2; }
  case "$f" in
    *.md|*.markdown)
      # Split out every ```mermaid ... ``` block.
      awk -v work="$WORK" -v src="$f" '
        /^[[:space:]]*```mermaid[[:space:]]*$/ { inblk=1; blk++; next }
        /^[[:space:]]*```[[:space:]]*$/        { if (inblk) { inblk=0 } ; next }
        inblk { print > (work "/md-" blk ".mmd") }
      ' "$f"
      for blk in "$WORK"/md-*.mmd; do
        [ -e "$blk" ] || continue
        n=$((n + 1))
        mv "$blk" "$WORK/d-$n.mmd"
        printf '%s\t%s\n' "$f" "$WORK/d-$n.mmd" >> "$WORK/index"
      done
      ;;
    *)
      n=$((n + 1))
      cp "$f" "$WORK/d-$n.mmd"
      printf '%s\t%s\n' "$f" "$WORK/d-$n.mmd" >> "$WORK/index"
      ;;
  esac
done

[ "$n" -gt 0 ] || { echo "FAIL: no mermaid diagrams found in the given files" >&2; exit 1; }

mkdir -p "$(dirname "$out")"

{
cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
HEAD
# Provenance: lets a consumer prove this render matches the current source
# without relying on filesystem timestamps (whole-second `-nt` is unreliable).
for f in "${files[@]}"; do
  printf '<meta name="rendered-from" content="%s" data-sha256="%s">\n' \
    "$(printf '%s' "$f" | html_escape)" "$(sha256_of "$f")"
done
printf '<title>%s</title>\n' "$(printf '%s' "$title" | html_escape)"
cat <<'STYLE'
<style>
  :root {
    --bg: #ffffff; --fg: #1a1a1a; --muted: #666; --card: #fafafa;
    --border: #e0e0e0; --accent: #4a5568;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#151719; --fg:#e8e8e8; --muted:#9aa0a6; --card:#1e2124; --border:#31363b; --accent:#a0aec0; }
  }
  :root[data-theme="dark"]  { --bg:#151719; --fg:#e8e8e8; --muted:#9aa0a6; --card:#1e2124; --border:#31363b; --accent:#a0aec0; }
  :root[data-theme="light"] { --bg:#ffffff; --fg:#1a1a1a; --muted:#666; --card:#fafafa; --border:#e0e0e0; --accent:#4a5568; }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 2rem 1.25rem 4rem; background: var(--bg); color: var(--fg);
    font: 15px/1.6 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  .wrap { max-width: 1100px; margin: 0 auto; }
  header { display: flex; align-items: baseline; gap: 1rem; flex-wrap: wrap;
           border-bottom: 1px solid var(--border); padding-bottom: 1rem; margin-bottom: 2rem; }
  h1 { font-size: 1.4rem; margin: 0; font-weight: 600; }
  .meta { color: var(--muted); font-size: .85rem; }
  .toggle { margin-left: auto; background: var(--card); color: var(--fg); border: 1px solid var(--border);
            border-radius: 6px; padding: .35rem .7rem; cursor: pointer; font-size: .8rem; }
  .card { background: var(--card); border: 1px solid var(--border); border-radius: 10px;
          padding: 1.25rem; margin-bottom: 1.75rem; }
  .card h2 { font-size: .95rem; margin: 0 0 .25rem; font-weight: 600; font-family: ui-monospace, monospace; }
  .sources { color: var(--muted); font-size: .8rem; margin: 0 0 1rem; font-family: ui-monospace, monospace; }
  .diagram { overflow-x: auto; }
  .mermaid { display: flex; justify-content: center; min-width: min-content; }
  .err { color: #c0392b; font-family: ui-monospace, monospace; font-size: .85rem; white-space: pre-wrap; }
  footer { color: var(--muted); font-size: .8rem; border-top: 1px solid var(--border); padding-top: 1rem; }
</style>
</head>
<body>
<div class="wrap">
<header>
STYLE
printf '  <h1>%s</h1>\n' "$(printf '%s' "$title" | html_escape)"
printf '  <span class="meta">%s diagram(s) · generated %s</span>\n' "$n" "$(date -u '+%Y-%m-%d %H:%M UTC')"
cat <<'HDR2'
  <button class="toggle" id="themeToggle" type="button">Toggle theme</button>
</header>
HDR2

while IFS=$'\t' read -r label body; do
  sources=$(grep -m1 '^%%[[:space:]]*sources:' "$body" 2>/dev/null || true)
  printf '<section class="card">\n'
  printf '  <h2>%s</h2>\n' "$(printf '%s' "$label" | html_escape)"
  if [ -n "$sources" ]; then
    printf '  <p class="sources">%s</p>\n' "$(printf '%s' "$sources" | html_escape)"
  fi
  printf '  <div class="diagram"><pre class="mermaid">'
  html_escape < "$body"
  printf '</pre></div>\n</section>\n'
done < "$WORK/index"

cat <<'TAIL'
<footer>Rendered with Mermaid. Review the design, then sign off with
<code>bash harness/gates/signoff.sh &lt;iteration-file&gt;</code>.</footer>
</div>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";

  const root = document.documentElement;
  const stored = localStorage.getItem("mmd-theme");
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  let dark = stored ? stored === "dark" : prefersDark;

  const sources = [...document.querySelectorAll("pre.mermaid")].map(el => el.textContent);

  async function render() {
    root.dataset.theme = dark ? "dark" : "light";
    mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "default", securityLevel: "strict" });
    const nodes = document.querySelectorAll("pre.mermaid");
    for (const [i, el] of nodes.entries()) {
      try {
        const { svg } = await mermaid.render("mmd-" + i + "-" + Date.now(), sources[i]);
        el.innerHTML = svg;
      } catch (e) {
        el.innerHTML = '<div class="err">Mermaid parse error: ' +
          String(e && e.message ? e.message : e).replace(/[<>&]/g, c => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" })[c]) +
          "</div>";
      }
    }
  }

  document.getElementById("themeToggle").addEventListener("click", () => {
    dark = !dark;
    localStorage.setItem("mmd-theme", dark ? "dark" : "light");
    render();
  });

  render();
</script>
</body>
</html>
TAIL
} > "$out"

echo "rendered $n diagram(s) -> $out"

if [ "$open_after" -eq 1 ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) start "" "$(cygpath -w "$out")" 2>/dev/null || true ;;
    Darwin)               open "$out" ;;
    *)                    xdg-open "$out" >/dev/null 2>&1 || true ;;
  esac
fi

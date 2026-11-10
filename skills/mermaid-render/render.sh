#!/usr/bin/env bash
# Render Mermaid diagrams into one reviewable HTML page.
#
# Usage:
#   render.sh -o OUT.html [--title TITLE] [--shared-lib] [--cdn] [--open] FILE...
#
# FILE may be:
#   *.mmd / *.mermaid  — one diagram per file
#   *.md               — every ```mermaid fenced block becomes a diagram
#
# Library modes (default: self-contained):
#   default        inline the vendored mermaid build — works offline, from
#                  file://, and under a strict CSP. Costs ~3.5 MB per page.
#   --shared-lib   write mermaid.min.js next to OUT.html and link it, so many
#                  pages in one directory share one copy. Best when the pages
#                  are committed (e.g. one per iteration).
#   --cdn          link the CDN copy. Smallest file, but renders nothing when
#                  offline or when external hosts are blocked.
#
# NOTE: use the UMD build, never mermaid.esm.min.mjs — the ESM file is a 29 KB
# loader that pulls dozens of relative chunks at view time. If any of them is
# blocked the page silently shows raw text instead of diagrams.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_LIB="$SCRIPT_DIR/vendor/mermaid.min.js"
CDN_URL="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"

out=""
title="Diagram Review"
open_after=0
lib_mode="inline"
files=()

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--out)      out="$2"; shift 2 ;;
    --title)       title="$2"; shift 2 ;;
    --shared-lib)  lib_mode="shared"; shift ;;
    --cdn)         lib_mode="cdn"; shift ;;
    --open)        open_after=1; shift ;;
    -h|--help)     sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            echo "unknown option: $1" >&2; exit 2 ;;
    *)             files+=("$1"); shift ;;
  esac
done

[ -n "$out" ] || { echo "FAIL: -o OUT.html is required" >&2; exit 2; }
[ "${#files[@]}" -gt 0 ] || { echo "FAIL: no input files" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Fetch the vendored library on first use, so the skill works offline later.
ensure_lib() {
  [ -s "$VENDOR_LIB" ] && return 0
  mkdir -p "$(dirname "$VENDOR_LIB")"
  echo "fetching mermaid (one-time, ~3.5 MB) …" >&2
  if curl -fsSL "$CDN_URL" -o "$VENDOR_LIB.tmp" 2>/dev/null && [ -s "$VENDOR_LIB.tmp" ]; then
    mv "$VENDOR_LIB.tmp" "$VENDOR_LIB"
    return 0
  fi
  rm -f "$VENDOR_LIB.tmp"
  return 1
}

if [ "$lib_mode" != "cdn" ] && ! ensure_lib; then
  echo "WARN: could not obtain mermaid locally; falling back to --cdn" >&2
  lib_mode="cdn"
fi

# Emits: <label>\t<path-to-diagram-body> per line, into $WORK/index
: > "$WORK/index"
n=0

for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "FAIL: no such file: $f" >&2; exit 2; }
  case "$f" in
    *.md|*.markdown)
      # Split out every ```mermaid ... ``` block.
      awk -v work="$WORK" '
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

# Place the shared library before opening the output stream, so nothing writes
# inside the redirect block that also produces $out.
if [ "$lib_mode" = "shared" ]; then
  shared_lib_path="$(dirname "$out")/mermaid.min.js"
  if [ "$shared_lib_path" -ef "$out" ] 2>/dev/null; then
    echo "FAIL: --shared-lib would overwrite the output file itself" >&2
    exit 2
  fi
  cp "$VENDOR_LIB" "$shared_lib_path"
fi

{
cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
HEAD
# Provenance: records which sources this page was rendered from. Freshness is
# the design gate's job and is mtime-based since meta-0004; this page carries
# no hash of its own.
for f in "${files[@]}"; do
  printf '<meta name="rendered-from" content="%s">\n' \
    "$(printf '%s' "$f" | html_escape)"
done
printf '<title>%s</title>\n' "$(printf '%s' "$title" | html_escape)"
cat <<'STYLE'
<style>
  :root {
    --bg: #ffffff; --fg: #1a1a1a; --muted: #666; --card: #fafafa;
    --border: #e0e0e0;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#151719; --fg:#e8e8e8; --muted:#9aa0a6; --card:#1e2124; --border:#31363b; }
  }
  :root[data-theme="dark"]  { --bg:#151719; --fg:#e8e8e8; --muted:#9aa0a6; --card:#1e2124; --border:#31363b; }
  :root[data-theme="light"] { --bg:#ffffff; --fg:#1a1a1a; --muted:#666; --card:#fafafa; --border:#e0e0e0; }
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
  /* Until mermaid replaces it, the source stays hidden — seeing raw code would
     be indistinguishable from a broken render. */
  .mermaid:not([data-rendered]) { display: none; }
  .banner { display: none; background: #fdf0ed; border: 1px solid #e6b0a5; color: #8c2f16;
            border-radius: 8px; padding: .9rem 1.1rem; margin-bottom: 1.5rem; font-size: .9rem; }
  .banner code { font-family: ui-monospace, monospace; }
  .err { color: #c0392b; font-family: ui-monospace, monospace; font-size: .85rem; white-space: pre-wrap; }
  .raw { font-family: ui-monospace, monospace; font-size: .8rem; white-space: pre-wrap;
         color: var(--muted); margin: 0; }
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
<div class="banner" id="banner">
  <strong>Mermaid could not be loaded</strong> — the diagram sources are shown below as text.
  Re-render without <code>--cdn</code> to embed the library in the page.
</div>
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
<footer>Rendered with Mermaid. Review the design, then approve it in conversation —
the agent records <code>approved_by: user</code> in the iteration file.</footer>
</div>
TAIL

# --- the library ---
case "$lib_mode" in
  inline)
    printf '<script>\n'
    # Guard against a literal </script> inside the bundle closing the tag early.
    sed 's|</script|<\\/script|g' "$VENDOR_LIB"
    printf '\n</script>\n'
    ;;
  shared)
    printf '<script src="mermaid.min.js"></script>\n'
    ;;
  cdn)
    printf '<script src="%s"></script>\n' "$CDN_URL"
    ;;
esac

cat <<'TAIL2'
<script>
  (function () {
    var root = document.documentElement;
    var stored = null;
    try { stored = localStorage.getItem("mmd-theme"); } catch (e) {}
    var dark = stored ? stored === "dark"
                      : window.matchMedia("(prefers-color-scheme: dark)").matches;

    var nodes = Array.prototype.slice.call(document.querySelectorAll("pre.mermaid"));
    var sources = nodes.map(function (el) { return el.textContent; });

    function showBanner() {
      document.getElementById("banner").style.display = "block";
      nodes.forEach(function (el, i) {
        el.setAttribute("data-rendered", "raw");
        el.innerHTML = '<pre class="raw"></pre>';
        el.firstChild.textContent = sources[i];
      });
    }

    function render() {
      root.dataset.theme = dark ? "dark" : "light";
      window.mermaid.initialize({
        startOnLoad: false,
        theme: dark ? "dark" : "default",
        securityLevel: "strict"
      });
      nodes.forEach(function (el, i) {
        var id = "mmd-" + i + "-" + Date.now();
        try {
          var r = window.mermaid.render(id, sources[i]);
          Promise.resolve(r).then(function (res) {
            el.innerHTML = res && res.svg ? res.svg : String(res);
            el.setAttribute("data-rendered", "ok");
          }).catch(function (e) { fail(el, e); });
        } catch (e) { fail(el, e); }
      });
    }

    function fail(el, e) {
      el.setAttribute("data-rendered", "error");
      el.innerHTML = '<div class="err"></div>';
      el.firstChild.textContent = "Mermaid parse error: " + (e && e.message ? e.message : e);
    }

    document.getElementById("themeToggle").addEventListener("click", function () {
      dark = !dark;
      try { localStorage.setItem("mmd-theme", dark ? "dark" : "light"); } catch (e) {}
      if (window.mermaid) { render(); }
    });

    if (window.mermaid) { render(); } else { showBanner(); }
  })();
</script>
</body>
</html>
TAIL2
} > "$out"

size=$(du -h "$out" | awk '{print $1}')
echo "rendered $n diagram(s) -> $out ($size, lib: $lib_mode)"

if [ "$open_after" -eq 1 ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) start "" "$(cygpath -w "$out")" 2>/dev/null || true ;;
    Darwin)               open "$out" ;;
    *)                    xdg-open "$out" >/dev/null 2>&1 || true ;;
  esac
fi

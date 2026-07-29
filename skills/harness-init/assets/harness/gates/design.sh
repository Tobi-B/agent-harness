#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh design.
#
# Iteration-scoped. The design must be *reviewable*: it carries at least one
# Mermaid diagram AND a rendered HTML page that is not older than the source,
# so the user approves a design they could actually look at.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="design"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

require_gate_passed plan

iter=$(require_current_iteration)

ITER_MD="$DOCS_DIR/iterations/${iter}.md"
ITER_HTML="$DOCS_DIR/iterations/${iter}.html"

[ -f "$ITER_MD" ] || fail "missing $ITER_MD (design the iteration first)"

for section in "## Goal" "## Approach" "## Affected Components" "## Test Strategy"; do
  grep -qF "$section" "$ITER_MD" || fail "$ITER_MD missing section: $section"
done

grep -q '^[[:space:]]*```mermaid' "$ITER_MD" \
  || fail "$ITER_MD has no \`\`\`mermaid diagram — the design must be visual"

# Stories named in the plan for this iteration must be referenced by the design.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  grep -qF "$s" "$ITER_MD" || fail "$ITER_MD does not reference story $s from the plan"
done

RENDER_CMD="bash ~/.claude/skills/mermaid-render/render.sh --shared-lib -o $ITER_HTML --title '$iter Design' $ITER_MD"

[ -f "$ITER_HTML" ] || fail "missing rendered $ITER_HTML — run: $RENDER_CMD"

# Freshness by content hash, not mtime: filesystem timestamps here compare at
# whole-second resolution, so a render right after a write looks "not newer".
grep -qF "$(sha256_of "$ITER_MD")" "$ITER_HTML" \
  || fail "$ITER_HTML does not match the current $ITER_MD (stale render) — re-run: $RENDER_CMD"

require_signed_off "$ITER_MD"

pass

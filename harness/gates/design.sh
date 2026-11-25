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

# meta-0010: the two questions a cold subagent would otherwise answer alone.
# The gate checks that they were answered (non-empty body, "none" is fine),
# not that the answer is good — that is what the design review is for.
section_body() {
  awk -v h="$2" '
    $0 == h { on = 1; next }
    on && /^## / { exit }
    on { print }
  ' "$1" | tr '
' ' ' | sed 's/<!--[^>]*-->//g' | tr -d '[:space:]'
}
for section in "## Interfaces" "## NFR impact"; do
  grep -qxF "$section" "$ITER_MD" || fail "$ITER_MD missing section: $section"
  [ -n "$(section_body "$ITER_MD" "$section")" ]     || fail "$ITER_MD has an empty '$section' section — name what it covers, or write 'none'"
done

grep -q '^[[:space:]]*```mermaid' "$ITER_MD" \
  || fail "$ITER_MD has no \`\`\`mermaid diagram — the design must be visual"

# Stories named in the plan for this iteration must be referenced by the design.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  grep -qwF "$s" "$ITER_MD" || fail "$ITER_MD does not reference story $s from the plan"
done

RENDER_CMD="bash ~/.claude/skills/mermaid-render/render.sh --shared-lib -o $ITER_HTML --title '$iter Design' $ITER_MD"

[ -f "$ITER_HTML" ] || fail "missing rendered $ITER_HTML — run: $RENDER_CMD"

# Freshness by mtime, checked only UNTIL the design is approved: what the user
# is about to look at must not be older than its source. Equal timestamps pass
# — filesystem seconds-resolution makes a render right after a write look
# simultaneous, and that is fine.
#
# Once approved, the check is over. Writing the approval marker itself makes
# the markdown newer than the render, which used to force a re-render after
# every approval; and `verify` later edits the same file. Material changes
# after approval are covered by the re-ask rule, not by a timestamp.
if ! approval_is_valid "$(approved_by_of "$ITER_MD")" && [ "$ITER_MD" -nt "$ITER_HTML" ]; then
  fail "$ITER_HTML is older than the current $ITER_MD (stale render) — re-run: $RENDER_CMD"
fi

require_approved "$ITER_MD"

pass

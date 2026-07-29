#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh verify.
#
# Iteration-scoped: did THIS iteration deliver what its design promised?
# Project-wide success criteria and NFRs are checked by the release gate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="verify"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

iter=$(require_current_iteration)
require_iteration_gate_passed "$iter" implement

ITER_MD="$DOCS_DIR/iterations/${iter}.md"
[ -f "$ITER_MD" ] || fail "missing $ITER_MD"

grep -qF "## Verification" "$ITER_MD" \
  || fail "$ITER_MD missing '## Verification' section — record the gate results for $iter"

# Each story in the iteration must be reported on in the Verification section.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  awk -v s="$s" '
    /^## Verification/ { inv=1; next }
    /^## / && inv { inv=0 }
    inv && index($0, s) { found=1 }
    END { exit !found }
  ' "$ITER_MD" || fail "$ITER_MD '## Verification' section does not report on story $s"
done

remaining=$(awk '
  /^## Verification/ { inv=1; next }
  /^## / && inv { inv=0 }
  inv && /^- \[ \]/ { n++ }
  END { print n+0 }
' "$ITER_MD")
[ "$remaining" -eq 0 ] \
  || fail "$ITER_MD has $remaining unchecked '- [ ]' items under '## Verification'"

pass

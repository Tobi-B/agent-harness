#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh verify.
#
# Iteration-scoped: did THIS iteration deliver what its design promised?
# Project-wide success criteria and NFRs are checked by the release gate.
#
# Evidence, not checkboxes (meta-0009): the gate runs test, lint and acceptance
# again — the code may have changed since implement passed. The checkboxes in
# '## Verification' are the agent's account; the commands are the evidence.
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

# The Verification section only (CR-tolerant for Windows checkouts).
section=$(awk '
  { sub(/\r$/, "") }
  /^## Verification/ { inv=1; next }
  /^## / && inv { inv=0 }
  inv
' "$ITER_MD")

# Each story in the iteration must be reported on in the Verification section.
# -w: US-001 must not be satisfied by a mention of US-0011.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  grep -qwF "$s" <<<"$section" \
    || fail "$ITER_MD '## Verification' section does not report on story $s"
done

remaining=$(grep -c '^- \[ \]' <<<"$section" || true)
[ "$remaining" -eq 0 ] \
  || fail "$ITER_MD has $remaining unchecked '- [ ]' items under '## Verification'"

run_project_commands "$iter"

pass

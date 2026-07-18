#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh verify.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="verify"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

REPORT="$DOCS_DIR/verify-report.md"
PRD="$DOCS_DIR/prd.md"

[ -f "$REPORT" ] || fail "missing $REPORT"

for phase in discover architect model implement; do
  require_gate_passed "$phase"
done

# Success Criteria / NFR checkboxes in the PRD must actually be checked off —
# an unchecked "- [ ]" item means the criterion is unmet or was never measured.
checked=$(grep -Ec '^- \[[xX]\]' "$PRD" || true)
unchecked=$(grep -Ec '^- \[ \]' "$PRD" || true)
[ "$checked" -gt 0 ] || fail "PRD has no checked '- [x]' Success Criteria / NFR items"
[ "$unchecked" -eq 0 ] \
  || fail "PRD still has $unchecked unchecked '- [ ]' items — verify each criterion and check it off, or remove non-applicable ones"

grep -qF "## Result" "$REPORT" || fail "$REPORT missing '## Result' section"
grep -qF "Success Criteria" "$REPORT" || fail "$REPORT missing 'Success Criteria' section"
grep -qF "NFR" "$REPORT" || fail "$REPORT missing 'NFR' section"

pass

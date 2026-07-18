#!/usr/bin/env bash
# Advance past a phase: run its (pure) gate, write the audit file, record the
# result in status.yaml, and move current_phase to the next phase.
#
# THIS IS THE PHASE TRANSITION — it requires user approval. Run it yourself,
# or pass --yes only when the user has explicitly told the agent to advance.
# Without --yes it asks for interactive confirmation, so an agent cannot
# advance silently.
#
# Usage: bash gates/advance.sh <phase> [--yes]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="advance"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

[ $# -ge 1 ] || fail "usage: bash gates/advance.sh <phase> [--yes]"
phase="$1"
shift
assume_yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) assume_yes=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

known=$(yq ".phases[] | select(.id == \"$phase\") | .id" "$WORKFLOW_FILE")
[ "$known" = "$phase" ] || fail "unknown phase '$phase' (not in workflow.yaml)"

[ -f "$SCRIPT_DIR/$phase.sh" ] || fail "no gate script gates/$phase.sh"

if [ "$assume_yes" -ne 1 ]; then
  if [ ! -t 0 ]; then
    fail "phase transitions require user approval: run interactively or pass --yes on explicit user instruction"
  fi
  printf "Advance past phase '%s'? [y/N] " "$phase"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "aborted"; exit 1 ;;
  esac
fi

echo "running gate: $phase"
bash "$SCRIPT_DIR/$phase.sh" || fail "gate '$phase' failed — not advancing"

ts=$(now_iso)
next=$(phase_next "$phase")

GATE_NAME="$phase" write_audit <<EOF
# Audit: phase $phase

- **result**: PASS
- **at**: $ts
- **next phase**: $next

## Signed-off artifacts at transition

$(yq -o=json '.signed_off_artifacts' "$STATUS_FILE" | jq -r '.[]? | "- \(.path) (sha256 \(.sha256[0:12])…, by \(.by), at \(.at))"')
EOF

set_status "$phase" "gate_passed" "true"
set_status "$phase" "completed_at" "$ts"

if [ "$next" = "null" ] || [ -z "$next" ]; then
  echo "workflow complete: '$phase' was the final phase"
else
  set_current_phase "$next"
  set_status "$next" "started_at" "$ts"
  echo "advanced: current_phase = $next"
fi

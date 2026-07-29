#!/usr/bin/env bash
# Advance past a phase: run its (pure) gate, write the audit file, record the
# result in status.yaml, and move to the next phase — looping back through the
# iteration cycle (design → implement → verify) until the plan is exhausted.
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

scope=$(phase_scope "$phase")
iter=""
if [ "$scope" = "iteration" ]; then
  iter=$(current_iteration)
  [ -n "$iter" ] || fail "phase '$phase' is iteration-scoped but status.yaml has no current_iteration"
fi

if [ "$assume_yes" -ne 1 ]; then
  if [ ! -t 0 ]; then
    fail "phase transitions require user approval: run interactively or pass --yes on explicit user instruction"
  fi
  if [ -n "$iter" ]; then
    printf "Advance past phase '%s' of iteration %s? [y/N] " "$phase" "$iter"
  else
    printf "Advance past phase '%s'? [y/N] " "$phase"
  fi
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "aborted"; exit 1 ;;
  esac
fi

echo "running gate: $phase${iter:+ ($iter)}"
bash "$SCRIPT_DIR/$phase.sh" || fail "gate '$phase' failed — not advancing"

ts=$(now_iso)

# --- decide where we go next -------------------------------------------------
# 'plan' opens the iteration cycle; 'verify' either loops back to design for the
# next iteration or closes the cycle. Everything else follows the static
# 'next:' declared in workflow.yaml.

next_iter=""
case "$phase" in
  plan)
    next=$(phase_next "$phase")
    next_iter=$(first_iteration_id)
    [ -n "$next_iter" ] || fail "plan.md lists no iterations to start"
    ;;
  verify)
    next_iter=$(next_iteration_id "$iter")
    if [ -n "$next_iter" ]; then
      next="design"
    else
      next=$(yq ".phases[] | select(.id == \"verify\") | .next_when_iterations_done" "$WORKFLOW_FILE")
    fi
    ;;
  *)
    next=$(phase_next "$phase")
    ;;
esac

GATE_NAME="$phase" write_audit <<EOF
# Audit: phase $phase${iter:+ — iteration $iter}

- **result**: PASS
- **at**: $ts
${iter:+- **iteration**: $iter}
- **next**: ${next}${next_iter:+ ($next_iter)}

## Signed-off artifacts at transition

$(yq -o=json '.signed_off_artifacts' "$STATUS_FILE" | jq -r '.[]? | "- \(.path) (sha256 \(.sha256[0:12])…, by \(.by), at \(.at))"')
EOF

if [ -n "$iter" ]; then
  set_iteration_status "$iter" "$phase" "gate_passed" "true"
  set_iteration_status "$iter" "$phase" "completed_at" "$ts"
else
  set_status "$phase" "gate_passed" "true"
  set_status "$phase" "completed_at" "$ts"
fi

if [ "$next" = "null" ] || [ -z "$next" ]; then
  set_current_iteration ""
  echo "workflow complete: '$phase' was the final phase"
  exit 0
fi

if [ -n "$next_iter" ]; then
  set_current_iteration "$next_iter"
  set_iteration_status "$next_iter" "$next" "started_at" "$ts"
  echo "advanced: current_phase = $next (iteration $next_iter)"
elif [ "$(phase_scope "$next")" = "iteration" ]; then
  set_iteration_status "$iter" "$next" "started_at" "$ts"
  echo "advanced: current_phase = $next (iteration $iter)"
else
  set_current_iteration ""
  set_status "$next" "started_at" "$ts"
  echo "advanced: current_phase = $next"
fi

set_current_phase "$next"

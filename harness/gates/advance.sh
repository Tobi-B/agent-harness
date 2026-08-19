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

# Autopilot stands in for the human prompt, but only inside the iteration cycle
# and only while it has budget. Everything else still stops here.
auto_advance=0
if [ "$assume_yes" -ne 1 ] && autopilot_active_for "$phase"; then
  auto_advance=1
  echo "autopilot: advancing '$phase'${iter:+ ($iter)} without asking"
fi

if [ "$assume_yes" -ne 1 ] && [ "$auto_advance" -ne 1 ]; then
  if [ ! -t 0 ]; then
    if autopilot_phase_in_scope "$phase"; then
      warn "$(autopilot_enabled_and_valid || true)"
    fi
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

# An iteration costs budget the first time autopilot carries any of its phases.
# Charging at 'design' would miss the case where the user hands over mid-cycle.
if [ "$auto_advance" -eq 1 ] && [ -n "$iter" ]; then
  autopilot_claim_iteration "$iter"
fi

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
- **approved by**: $([ "$auto_advance" -eq 1 ] \
    && echo "autopilot($(autopilot_field enabled_by)) — expires $(autopilot_field expires_at), $(autopilot_field iterations_used)/$(autopilot_field max_iterations) iterations used" \
    || echo "user")

## Approved artifacts at transition

$(grep -rlE '^(#[[:space:]]*)?approved_by:' "$DOCS_DIR" "$HARNESS_ROOT/tests/features" 2>/dev/null | sort | while read -r f; do
    who=$(approved_by_of "$f")
    [ -n "$who" ] && echo "- $(rel_to_root "$f") (approved by $who)"
  done)
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

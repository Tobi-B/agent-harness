#!/usr/bin/env bash
# Advance past a phase: run its (pure) gate, record the result in status.yaml,
# write the audit file, and move to the next phase — looping back through the
# iteration cycle (design → implement → verify) until the plan is exhausted.
#
# THIS IS THE PHASE TRANSITION. Three things can let it happen:
#   * the user, answering the prompt in a terminal;
#   * --yes, which the agent may pass only when the user explicitly told it to
#     advance (the harness cannot tell who asked; the audit says "--yes");
#   * autopilot, for the phases its mode carries — see _lib.sh. In mode
#     `build` that is design/implement/verify, and the design gate still only
#     passes for a design the user approved.
# Anything else stops here, so an agent cannot advance silently.
#
# Usage: bash gates/advance.sh <phase> [--yes]
#        bash gates/advance.sh reopen [--yes]   (back from release, see below)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="advance"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

[ $# -ge 1 ] || fail "usage: bash gates/advance.sh <phase|reopen> [--yes]"
phase="$1"
shift
assume_yes=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) assume_yes=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

# --- reopen: the one way back from release (meta-0010) ------------------------
#
# A finding at release can need an iteration of its own. The phase machine only
# moves forward, so this is the explicit, decision-gated exception: the user
# answered a decision that references plan.md, and plan.md now lists an
# iteration that has not been through design/implement/verify. Always the
# user's (--yes or the prompt) - autopilot never carries it, release being
# the user's. One decision reopens once.
if [ "$phase" = "reopen" ]; then
  current=$(yq '.current_phase' "$STATUS_FILE")
  [ "$current" = "release" ] \
    || fail "reopen goes back from 'release' (current_phase: $current)"
  [ "$(yq '.phases.release.gate_passed // false' "$STATUS_FILE")" != "true" ] \
    || fail "release has already passed - the workflow is complete, there is nothing to reopen"

  dec=$(reopen_decisions plan.md | head -n 1 || true)
  [ -n "$dec" ] \
    || fail "no answered decision (approved_by: user) that references plan.md and is still unused - open one: what changes in the plan, and why"
  dec_id="${dec%%$'\t'*}"

  bash "$SCRIPT_DIR/plan.sh" >/dev/null 2>&1 \
    || fail "plan.md does not pass its gate (bash gates/plan.sh) - the changed plan needs the user's approval marker and must cover every story"

  new_iter=""
  while read -r id; do
    [ -n "$id" ] || continue
    if [ "$(iteration_gate_passed "$id" design)" != "true" ] \
       || [ "$(iteration_gate_passed "$id" implement)" != "true" ] \
       || [ "$(iteration_gate_passed "$id" verify)" != "true" ]; then
      new_iter="$id"
      break
    fi
  done < <(plan_iteration_ids)
  [ -n "$new_iter" ] \
    || fail "plan.md lists no iteration that still has to go through design, implement and verify - add one first"

  if [ "$assume_yes" -eq 1 ]; then
    via="--yes (the harness cannot tell who asked for it)"
  elif [ ! -t 0 ]; then
    fail "reopen requires user approval: run interactively or pass --yes on explicit user instruction"
  else
    printf "Reopen the workflow from release, as %s (decision %s)? [y/N] " "$new_iter" "$dec_id"
    read -r answer
    case "$answer" in
      y|Y|yes|YES) via="interactive" ;;
      *) echo "aborted"; exit 1 ;;
    esac
  fi

  ts=$(now_iso)
  expr=".current_phase = \"design\" | .current_iteration = \"${new_iter}\""
  expr="$expr | .iterations.\"${new_iter}\".design.started_at = \"${ts}\""
  expr="$expr | .phases.release.gate_passed = false | .phases.release.started_at = null | .phases.release.completed_at = null"
  expr="$expr | .reopens = ((.reopens // []) + [\"${dec_id}\"]) | .last_updated = \"${ts}\""
  status_apply "$expr"

  GATE_NAME="reopen" write_audit <<EOF
# Audit: reopen from release

- **result**: PASS
- **at**: $ts
- **iteration**: $new_iter
- **next**: design ($new_iter)
- **transition via**: reopen ($dec_id) - $via
EOF
  echo "reopened: current_phase = design (iteration $new_iter), decision $dec_id spent"
  exit 0
fi

known=$(yq ".phases[] | select(.id == \"$phase\") | .id" "$WORKFLOW_FILE")
[ "$known" = "$phase" ] || fail "unknown phase '$phase' (not in workflow.yaml)"

[ -f "$SCRIPT_DIR/$phase.sh" ] || fail "no gate script gates/$phase.sh"

# Only the CURRENT phase can be advanced. Advancing an earlier phase whose gate
# still passes would rewind current_phase and wipe current_iteration; advancing
# a later one would skip work. The one way back is `reopen`, from release (below).
current=$(yq '.current_phase' "$STATUS_FILE")
[ "$phase" = "$current" ] \
  || fail "'$phase' is not the current phase (current_phase: $current) — only the current phase can be advanced"
if [ "$(phase_scope "$phase")" = "once" ] \
   && [ "$(yq ".phases.${phase}.gate_passed // false" "$STATUS_FILE")" = "true" ]; then
  fail "phase '$phase' has already passed its gate"
fi

scope=$(phase_scope "$phase")
iter=""
if [ "$scope" = "iteration" ]; then
  iter=$(current_iteration)
  [ -n "$iter" ] || fail "phase '$phase' is iteration-scoped but status.yaml has no current_iteration"
fi

# --- who lets this transition happen? ------------------------------------------
auto_advance=0
via=""
if [ "$assume_yes" -eq 1 ]; then
  via="--yes (the harness cannot tell who asked for it)"
elif block=$(autopilot_block_reason "$phase"); then
  auto_advance=1
  echo "autopilot: advancing '$phase'${iter:+ ($iter)} without asking"
elif [ ! -t 0 ]; then
  warn "$block"
  fail "phase transitions require user approval: run interactively or pass --yes on explicit user instruction"
else
  if [ -n "$iter" ]; then
    printf "Advance past phase '%s' of iteration %s? [y/N] " "$phase" "$iter"
  else
    printf "Advance past phase '%s'? [y/N] " "$phase"
  fi
  read -r answer
  case "$answer" in
    y|Y|yes|YES) via="interactive" ;;
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
final=0
if [ "$next" = "null" ] || [ -z "$next" ]; then
  final=1
fi

# --- record it: ONE write ------------------------------------------------------
# Every change this transition makes to status.yaml goes into a single yq call,
# so an interruption leaves the file either as it was or fully advanced.
expr=""
add() { expr="${expr:+$expr | }$1"; }

if [ -n "$iter" ]; then
  add ".iterations.\"${iter}\".${phase}.gate_passed = true"
  add ".iterations.\"${iter}\".${phase}.completed_at = \"${ts}\""
else
  add ".phases.${phase}.gate_passed = true"
  add ".phases.${phase}.completed_at = \"${ts}\""
fi

if [ "$final" -eq 1 ]; then
  add ".current_iteration = null"
elif [ -n "$next_iter" ]; then
  add ".current_iteration = \"${next_iter}\""
  add ".iterations.\"${next_iter}\".${next}.started_at = \"${ts}\""
  add ".current_phase = \"${next}\""
elif [ "$(phase_scope "$next")" = "iteration" ]; then
  add ".iterations.\"${iter}\".${next}.started_at = \"${ts}\""
  add ".current_phase = \"${next}\""
else
  add ".current_iteration = null"
  add ".phases.${next}.started_at = \"${ts}\""
  add ".current_phase = \"${next}\""
fi

# An iteration costs budget the first time autopilot carries any of its phases.
# Charging at 'design' would miss the case where the user hands over mid-cycle.
if [ "$auto_advance" -eq 1 ] && [ -n "$iter" ]; then
  claim=$(autopilot_claim_expr "$iter")
  [ -z "$claim" ] || add "$claim"
fi
add ".last_updated = \"${ts}\""

status_apply "$expr"

if [ "$auto_advance" -eq 1 ]; then
  via="autopilot($(autopilot_mode), enabled by $(autopilot_field enabled_by)) — expires $(autopilot_field expires_at), $(autopilot_field iterations_used)/$(autopilot_field max_iterations) iterations used"
fi

GATE_NAME="$phase" write_audit <<EOF
# Audit: phase $phase${iter:+ — iteration $iter}

- **result**: PASS
- **at**: $ts
${iter:+- **iteration**: $iter}
- **next**: ${next}${next_iter:+ ($next_iter)}
- **transition via**: $via

## Approved artifacts at transition

$(grep -rlE '^(#[[:space:]]*)?approved_by:' "$DOCS_DIR" "$HARNESS_ROOT/tests/features" 2>/dev/null | sort | while read -r f; do
    who=$(approved_by_of "$f")
    [ -n "$who" ] && echo "- $(rel_to_root "$f") (approved by $who)"
  done)
EOF

if [ "$final" -eq 1 ]; then
  echo "workflow complete: '$phase' was the final phase"
elif [ -n "$next_iter" ]; then
  echo "advanced: current_phase = $next (iteration $next_iter)"
elif [ -n "$iter" ] && [ "$(phase_scope "$next")" = "iteration" ]; then
  echo "advanced: current_phase = $next (iteration $iter)"
else
  echo "advanced: current_phase = $next"
fi

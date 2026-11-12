#!/usr/bin/env bash
# What now? Pure check — no state mutation. The one question a loop asks at
# the start of every tick, instead of re-deriving the answer from status.yaml,
# workflow.yaml and a gate run.
#
# Prints the current phase, the gate's verdict, the autopilot state, ONE action
# and — when it is the human's move — what exactly is waiting for them.
#
# Exit codes (the contract for any loop driver):
#   0  the agent may go on:   action work (gate red) or advance (gate green)
#   3  the human's move:      an approval, an open decision, a transition that
#                             is theirs, or a phase that stalled
#   4  done:                  release has passed
#   2  environment broken
#
#   while bash harness/gates/next.sh; do <one tick of the agent>; done
#
# It never decides where the machine goes next — advance.sh does. It asks the
# same predicate advance.sh asks (autopilot_block_reason), so "advance" here
# means advance.sh will not stop for a prompt.
#
# Usage: bash gates/next.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="next"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

phase=$(yq '.current_phase' "$STATUS_FILE")
iter=$(current_iteration)
[ -f "$SCRIPT_DIR/$phase.sh" ] || fail "current_phase '$phase' has no gate script"

say() { printf '%-12s %s\n' "$1:" "$2"; }

say phase "$phase"
say iteration "${iter:--}"

if reason=$(autopilot_on_and_unexpired); then
  say autopilot "on (mode: $(autopilot_mode))"
else
  say autopilot "off ($reason)"
fi

# Finished: release is the final phase and stays current once it has passed.
if [ "$phase" = "release" ] \
   && [ "$(yq '.phases.release.gate_passed // false' "$STATUS_FILE")" = "true" ]; then
  say gate "passed"
  say action "done"
  exit 4
fi

set +e
gate_out=$(bash "$SCRIPT_DIR/$phase.sh" 2>&1)
gate_rc=$?
set -e

carried=0
block=""
if block=$(autopilot_block_reason "$phase"); then
  carried=1
fi
open=$(open_decisions)

advance_cmd="bash harness/gates/advance.sh $phase"
gate_tail() { printf '%s\n' "$gate_out" | sed 's/^/  /'; }

case "$gate_rc" in
  0) say gate "pass" ;;
  1) say gate "fail — work needed" ;;
  3) say gate "waiting for an approval" ;;
  *) say gate "error (exit $gate_rc)" ;;
esac

# The environment comes first: nothing else can be trusted while it is broken.
if [ "$gate_rc" -ne 0 ] && [ "$gate_rc" -ne 1 ] && [ "$gate_rc" -ne 3 ]; then
  say action "stop"
  gate_tail
  exit 2
fi

# An open decision outranks everything: the agent asked, the user has not
# answered, and nothing moves until they do.
if [ -n "$open" ]; then
  say action "await_human"
  say needs_human "decide — answer in chat, the agent then records approved_by: user"
  printf '%s\n' "$open" | sed 's/^/  /'
  exit 3
fi

# The tripwire (meta-0009): while autopilot is on, something the user decided
# changed and no answered decision covers it. Same rank as an open decision.
if autopilot_on_and_unexpired >/dev/null 2>&1; then
  changed=$(tripwire_changes)
  if [ -n "$changed" ]; then
    say action "await_human"
    say needs_human "decided artifacts changed under autopilot — open a decision that references them, or the user re-enables autopilot to accept the change"
    printf '%s\n' "$changed" | sed 's/^/  /'
    exit 3
  fi
fi

case "$gate_rc" in
  3)
    # Only the human's word is missing. In mode full autopilot may give it.
    if [ "$carried" -eq 1 ] && autopilot_may_approve; then
      say action "approve"
      say note "mode full: mark what you drafted approved_by: autopilot, never user"
      gate_tail
      exit 0
    fi
    say action "await_human"
    say needs_human "approve — say so in chat, the agent then records approved_by: user"
    gate_tail
    exit 3
    ;;
  0)
    if [ "$carried" -eq 1 ]; then
      say action "advance"
      say run "$advance_cmd"
      exit 0
    fi
    say action "await_human"
    say needs_human "the transition is yours: $advance_cmd"
    say because "$block"
    exit 3
    ;;
  1)
    if [ "$carried" -eq 1 ]; then
      if phase_stalled "$phase"; then
        say action "await_human"
        say needs_human "stalled: '$phase' has been red longer than the phase timeout ($(autopilot_field phase_timeout_s)s)"
        gate_tail
        exit 3
      fi
      say action "work"
      say unattended "yes"
      gate_tail
      exit 0
    fi
    # Work to do, but nothing carries this phase: fine with the user in the
    # conversation, not something a loop should grind on alone.
    say action "work"
    say unattended "no ($block)"
    gate_tail
    exit 3
    ;;
esac

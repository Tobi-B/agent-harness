#!/usr/bin/env bash
# Turn auto mode on or off. Off = human-in-the-loop development cycle (the
# user approves every artifact and every transition). On, in one of two modes:
#
#   build  (default) the user decides, the agent builds. Autopilot carries the
#          transitions of design/implement/verify and approves NOTHING: every
#          story, ADR, plan and iteration design still needs the user. Designs
#          may be approved ahead; the loop runs until it reaches one that is not.
#   full   no human in the loop except release: the agent runs every other
#          phase alone and marks its own artifacts 'approved_by: autopilot'.
#
# ENABLING IS THE USER'S DECISION: the agent may run 'autopilot.sh on' only
# when the user explicitly asked for auto mode in conversation — never on its
# own initiative — and 'full' only when the user asked for exactly that. Bounds:
#
#   * release — always needs a human, in both modes.
#   * budget  — it expires (wall clock) and is capped in iterations, so a
#               forgotten autopilot cannot run away.
#   * stall   — optional: a phase that stays red longer than --phase-timeout
#               is handed back to the user by next.sh.
#   * audit   — enabling it, and every transition it carries, is written to
#               the audit trail.
#
# Usage:
#   bash gates/autopilot.sh on [--mode build|full] [--expires 8h]
#                              [--max-iterations 3] [--phase-timeout 2h] [--by NAME]
#   bash gates/autopilot.sh off
#   bash gates/autopilot.sh status
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="autopilot"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

[ $# -ge 1 ] || { usage; exit 2; }
action="$1"; shift

# Every option takes a value; say so instead of dying on an unbound $2.
need_value() {
  [ $# -ge 2 ] || fail "$1 needs a value"
}

case "$action" in
  status)
    print_autopilot_status
    # Exit 0 = on and unexpired. The budget is deliberately not part of this:
    # an iteration that spent the last unit still finishes, and whether
    # autopilot carries a given phase is next.sh's answer, not this one's.
    autopilot_on_and_unexpired >/dev/null 2>&1
    ;;

  off)
    status_apply ".autopilot.enabled = false | .autopilot.disabled_at = \"$(now_iso)\" | .last_updated = \"$(now_iso)\""
    echo "autopilot: OFF — every phase transition needs your approval again"
    ;;

  on)
    mode="build"
    expires="8h"
    max_iterations=3
    phase_timeout="0"
    by=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --mode)           need_value "$@"; mode="$2"; shift 2 ;;
        --expires)        need_value "$@"; expires="$2"; shift 2 ;;
        --max-iterations) need_value "$@"; max_iterations="$2"; shift 2 ;;
        --phase-timeout)  need_value "$@"; phase_timeout="$2"; shift 2 ;;
        --by)             need_value "$@"; by="$2"; shift 2 ;;
        *) fail "unknown argument: $1" ;;
      esac
    done

    # Deliberately runnable without a terminal: the user enables auto mode by
    # saying so in chat, and the agent runs this command for them. The rule
    # that the agent does this ONLY on explicit user instruction is an
    # instruction (AGENTS.md), not a mechanism — the expiry and iteration
    # budget below are the mechanical emergency brake.

    case "$mode" in
      build|full) ;;
      *) fail "--mode must be 'build' or 'full' (got '$mode')" ;;
    esac

    case "$max_iterations" in
      ''|*[!0-9]*) fail "--max-iterations must be a whole number" ;;
    esac
    [ "$max_iterations" -ge 1 ] || fail "--max-iterations must be at least 1"

    seconds=$(duration_to_seconds "$expires") \
      || fail "cannot read --expires '$expires' (use forms like 45m, 8h, 2d)"
    [ "$seconds" -le 259200 ] \
      || fail "--expires is capped at 3d — re-enable it if you still want it running"

    timeout_s=$(duration_to_seconds "$phase_timeout") \
      || fail "cannot read --phase-timeout '$phase_timeout' (use forms like 45m, 2h; 0 = off)"

    [ -n "$by" ] || by=$(git config user.name 2>/dev/null || true)
    [ -n "$by" ] || by="${USER:-${USERNAME:-unknown}}"

    ts=$(now_iso)
    expires_at=$(iso_in_seconds "$seconds")

    export AP_BY="$by" AP_AT="$ts" AP_EXP="$expires_at" AP_MODE="$mode"
    status_apply "
      .autopilot.enabled = true
      | .autopilot.mode = strenv(AP_MODE)
      | .autopilot.enabled_by = strenv(AP_BY)
      | .autopilot.enabled_at = strenv(AP_AT)
      | .autopilot.expires_at = strenv(AP_EXP)
      | .autopilot.max_iterations = ${max_iterations}
      | .autopilot.iterations_used = 0
      | .autopilot.iterations_claimed = []
      | .autopilot.phase_timeout_s = ${timeout_s}
      | .autopilot.disabled_at = null
      | del(.autopilot.scope)
      | .last_updated = strenv(AP_AT)"

    if [ "$mode" = "full" ]; then
      carries="discover → architect → model → plan → ⟳(design → implement → verify)"
      approves="its own artifacts, marked 'approved_by: autopilot'"
    else
      carries="the transitions of design → implement → verify"
      approves="nothing — stories, ADRs, the plan and every design stay with you"
    fi
    stall="off"
    [ "$timeout_s" -gt 0 ] && stall="a phase red for more than ${phase_timeout} comes back to you"

    # Enabling resets the budget and the stall clock; that should leave a trace.
    write_audit >/dev/null <<EOF
# Audit: autopilot enabled

- **at**: $ts
- **mode**: $mode
- **enabled by**: $by
- **expires**: $expires_at
- **budget**: $max_iterations iteration(s)
- **phase timeout**: $stall
EOF

    cat <<EOF
autopilot: ON (mode: $mode)
  carries:    $carries
  approves:   $approves
  expires:    $expires_at
  budget:     $max_iterations iteration(s)
  stall:      $stall
  enabled by: $by

release always stops for your approval, and so does any open decision.
Ask what comes next:  bash gates/next.sh
Turn it off any time: bash gates/autopilot.sh off
EOF
    ;;

  *)
    usage
    exit 2
    ;;
esac

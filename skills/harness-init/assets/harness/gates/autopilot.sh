#!/usr/bin/env bash
# Turn auto mode on or off. Off = human-in-the-loop development cycle (the
# user approves every artifact and every transition). On = the agent runs the
# cycle alone, without a human in the loop — except release.
#
# ENABLING IS THE USER'S DECISION: the agent may run 'autopilot.sh on' only
# when the user explicitly asked for auto mode in conversation — never on its
# own initiative. Bounds:
#
#   * scope   — every phase except release. The final release transition
#               always needs a human, so a fully auto run still ends in
#               front of a person.
#   * budget  — it expires (wall clock) and is capped in iterations, so a
#               forgotten autopilot cannot run away.
#   * audit   — auto-advances are attributed to "autopilot(<user>)" in the
#               audit trail, and auto-approved artifacts carry
#               "approved_by: autopilot", so it stays visible what a human
#               actually read and what a machine waved through.
#
# Usage:
#   bash gates/autopilot.sh on [--expires 8h] [--max-iterations 3] [--by NAME]
#   bash gates/autopilot.sh off
#   bash gates/autopilot.sh status
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="autopilot"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

[ $# -ge 1 ] || { usage; exit 2; }
action="$1"; shift

case "$action" in
  status)
    print_autopilot_status
    autopilot_enabled_and_valid >/dev/null 2>&1
    ;;

  off)
    yq -i '.autopilot.enabled = false' "$STATUS_FILE"
    yq -i ".autopilot.disabled_at = \"$(now_iso)\"" "$STATUS_FILE"
    yq -i ".last_updated = \"$(now_iso)\"" "$STATUS_FILE"
    echo "autopilot: OFF — every phase transition needs your approval again"
    ;;

  on)
    expires="8h"
    max_iterations=3
    by=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --expires)        expires="$2"; shift 2 ;;
        --max-iterations) max_iterations="$2"; shift 2 ;;
        --by)             by="$2"; shift 2 ;;
        *) fail "unknown argument: $1" ;;
      esac
    done

    # Deliberately runnable without a terminal: the user enables auto mode by
    # saying so in chat, and the agent runs this command for them. The rule
    # that the agent does this ONLY on explicit user instruction is an
    # instruction (AGENTS.md), not a mechanism — the expiry and iteration
    # budget below are the mechanical emergency brake.

    case "$max_iterations" in
      ''|*[!0-9]*) fail "--max-iterations must be a whole number" ;;
    esac
    [ "$max_iterations" -ge 1 ] || fail "--max-iterations must be at least 1"

    seconds=$(duration_to_seconds "$expires") \
      || fail "cannot read --expires '$expires' (use forms like 45m, 8h, 2d)"
    [ "$seconds" -le 259200 ] \
      || fail "--expires is capped at 3d — re-enable it if you still want it running"

    [ -n "$by" ] || by=$(git config user.name 2>/dev/null || true)
    [ -n "$by" ] || by="${USER:-${USERNAME:-unknown}}"

    ts=$(now_iso)
    expires_at=$(iso_in_seconds "$seconds")

    export AP_BY="$by" AP_AT="$ts" AP_EXP="$expires_at"
    yq -i '.autopilot.enabled = true' "$STATUS_FILE"
    yq -i '.autopilot.scope = "all_but_release"' "$STATUS_FILE"
    yq -i '.autopilot.enabled_by = strenv(AP_BY)' "$STATUS_FILE"
    yq -i '.autopilot.enabled_at = strenv(AP_AT)' "$STATUS_FILE"
    yq -i '.autopilot.expires_at = strenv(AP_EXP)' "$STATUS_FILE"
    yq -i ".autopilot.max_iterations = ${max_iterations}" "$STATUS_FILE"
    yq -i '.autopilot.iterations_used = 0' "$STATUS_FILE"
    yq -i '.autopilot.iterations_claimed = []' "$STATUS_FILE"
    yq -i '.autopilot.disabled_at = null' "$STATUS_FILE"
    yq -i ".last_updated = \"$ts\"" "$STATUS_FILE"

    cat <<EOF
autopilot: ON — no human in the loop until it expires or you turn it off
  scope:      discover → architect → model → plan → ⟳(design → implement → verify)
  expires:    $expires_at
  budget:     $max_iterations iteration(s)
  enabled by: $by

release always stops for your approval.
Turn it off any time: bash gates/autopilot.sh off
EOF
    ;;

  *)
    usage
    exit 2
    ;;
esac

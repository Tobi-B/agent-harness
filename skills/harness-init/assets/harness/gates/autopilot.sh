#!/usr/bin/env bash
# Turn auto-approve on or off for the iteration cycle.
#
# THIS SCRIPT IS RUN BY THE USER, NOT THE AGENT. Enabling requires an
# interactive terminal, so an agent in a non-interactive session cannot switch
# it on. It is deliberately narrow:
#
#   * scope   — only design/implement/verify. discover, architect, model, plan
#               and release always need a human sign-off, because that is where
#               the load-bearing decisions are made.
#   * budget  — it expires (wall clock) and is capped in iterations, so a
#               forgotten autopilot cannot run away.
#   * audit   — auto sign-offs are recorded as by "autopilot(<user>)" with
#               auto: true, so the registry always shows what a human actually
#               read and what a machine waved through.
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
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
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
    echo "autopilot: OFF — every gate needs your sign-off again"
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

    # An agent must not be able to grant itself autonomy. Requiring a terminal
    # is the same barrier advance.sh uses — weak against a determined operator,
    # but it does stop the ordinary non-interactive agent session.
    if [ ! -t 0 ] && [ "${HARNESS_AUTOPILOT_I_AM_HUMAN:-}" != "1" ]; then
      fail "enabling autopilot requires an interactive terminal — run it yourself"
    fi

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
    yq -i '.autopilot.scope = "iteration_cycle"' "$STATUS_FILE"
    yq -i '.autopilot.enabled_by = strenv(AP_BY)' "$STATUS_FILE"
    yq -i '.autopilot.enabled_at = strenv(AP_AT)' "$STATUS_FILE"
    yq -i '.autopilot.expires_at = strenv(AP_EXP)' "$STATUS_FILE"
    yq -i ".autopilot.max_iterations = ${max_iterations}" "$STATUS_FILE"
    yq -i '.autopilot.iterations_used = 0' "$STATUS_FILE"
    yq -i '.autopilot.iterations_claimed = []' "$STATUS_FILE"
    yq -i '.autopilot.disabled_at = null' "$STATUS_FILE"
    yq -i ".last_updated = \"$ts\"" "$STATUS_FILE"

    cat <<EOF
autopilot: ON
  scope:      design → implement → verify (iteration cycle only)
  expires:    $expires_at
  budget:     $max_iterations iteration(s)
  enabled by: $by

discover, architect, model, plan and release still stop for your sign-off.
Turn it off any time: bash gates/autopilot.sh off
EOF
    ;;

  *)
    usage
    exit 2
    ;;
esac

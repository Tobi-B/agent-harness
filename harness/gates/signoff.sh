#!/usr/bin/env bash
# Record a user sign-off for an artifact.
#
# THIS SCRIPT IS RUN BY THE USER, NOT THE AGENT. The sign-off registry in
# status.yaml (path + sha256 + by + at) is the single authority on approvals;
# frontmatter status fields are informational only. Gates verify the recorded
# hash against the file's current content, so any edit after sign-off is
# detected and requires a fresh sign-off.
#
# The one exception is --auto, which the agent may use while autopilot is on.
# It only signs iteration-cycle artifacts (docs/iterations/ITER-*), refuses
# outright when autopilot is off or out of budget, and marks the entry
# auto: true so the registry never blurs machine and human approval.
#
# Usage: bash gates/signoff.sh <artifact-path> [--by <name>] [--auto]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="signoff"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

[ $# -ge 1 ] || fail "usage: bash gates/signoff.sh <artifact-path> [--by <name>] [--auto]"

artifact="$1"
shift
by=""
auto=0
while [ $# -gt 0 ]; do
  case "$1" in
    --by) by="$2"; shift 2 ;;
    --auto) auto=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

# Accept paths relative to the harness root, the CWD, or absolute.
if [ -f "$HARNESS_ROOT/$artifact" ]; then
  file="$HARNESS_ROOT/$artifact"
elif [ -f "$artifact" ]; then
  file="$artifact"
else
  fail "artifact not found: $artifact"
fi

rel=$(rel_to_root "$file")
hash=$(sha256_of "$file")

if [ "$auto" -eq 1 ]; then
  case "$rel" in
    docs/iterations/ITER-*) ;;
    *) fail "--auto only signs iteration-cycle artifacts (docs/iterations/ITER-*), not $rel — this one needs a human" ;;
  esac
  if ! reason=$(autopilot_enabled_and_valid); then
    fail "--auto refused: $reason (user runs: bash gates/autopilot.sh on)"
  fi
  by="autopilot($(autopilot_field enabled_by))"
elif [ -z "$by" ]; then
  by=$(git config user.name 2>/dev/null || true)
fi
if [ -z "$by" ]; then
  by="${USER:-${USERNAME:-unknown}}"
fi

ts=$(now_iso)

yq -i "del(.signed_off_artifacts[] | select(.path == \"$rel\"))" "$STATUS_FILE"
export SIGNOFF_PATH="$rel" SIGNOFF_HASH="$hash" SIGNOFF_BY="$by" SIGNOFF_AT="$ts"
export SIGNOFF_AUTO=$([ "$auto" -eq 1 ] && echo true || echo false)
yq -i '.signed_off_artifacts += [{
  "path": strenv(SIGNOFF_PATH),
  "sha256": strenv(SIGNOFF_HASH),
  "by": strenv(SIGNOFF_BY),
  "at": strenv(SIGNOFF_AT),
  "auto": (strenv(SIGNOFF_AUTO) == "true")
}]' "$STATUS_FILE"
yq -i ".last_updated = \"$ts\"" "$STATUS_FILE"

echo "signed off: $rel"
echo "  sha256: $hash"
echo "  by:     $by"
echo "  at:     $ts"
if [ "$auto" -eq 1 ]; then
  echo "  auto:   true (autopilot — no human read this)"
fi

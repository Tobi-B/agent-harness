#!/usr/bin/env bash
# Record a user sign-off for an artifact.
#
# THIS SCRIPT IS RUN BY THE USER, NOT THE AGENT. The sign-off registry in
# status.yaml (path + sha256 + by + at) is the single authority on approvals;
# frontmatter status fields are informational only. Gates verify the recorded
# hash against the file's current content, so any edit after sign-off is
# detected and requires a fresh sign-off.
#
# Usage: bash gates/signoff.sh <artifact-path> [--by <name>]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="signoff"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

[ $# -ge 1 ] || fail "usage: bash gates/signoff.sh <artifact-path> [--by <name>]"

artifact="$1"
shift
by=""
while [ $# -gt 0 ]; do
  case "$1" in
    --by) by="$2"; shift 2 ;;
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

if [ -z "$by" ]; then
  by=$(git config user.name 2>/dev/null || true)
fi
if [ -z "$by" ]; then
  by="${USER:-${USERNAME:-unknown}}"
fi

ts=$(now_iso)

yq -i "del(.signed_off_artifacts[] | select(.path == \"$rel\"))" "$STATUS_FILE"
export SIGNOFF_PATH="$rel" SIGNOFF_HASH="$hash" SIGNOFF_BY="$by" SIGNOFF_AT="$ts"
yq -i '.signed_off_artifacts += [{
  "path": strenv(SIGNOFF_PATH),
  "sha256": strenv(SIGNOFF_HASH),
  "by": strenv(SIGNOFF_BY),
  "at": strenv(SIGNOFF_AT)
}]' "$STATUS_FILE"
yq -i ".last_updated = \"$ts\"" "$STATUS_FILE"

echo "signed off: $rel"
echo "  sha256: $hash"
echo "  by:     $by"
echo "  at:     $ts"

#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh discover.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="discover"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

PRD="$DOCS_DIR/prd.md"
STORIES_DIR="$DOCS_DIR/user_stories"
FEATURES_DIR="$HARNESS_ROOT/tests/features"

[ -f "$PRD" ] || fail "missing $PRD"
grep -q "^## Goals" "$PRD" || fail "PRD missing ## Goals"
grep -q "^## Non-Functional Requirements" "$PRD" || fail "PRD missing ## Non-Functional Requirements"
grep -q "^## Success Criteria" "$PRD" || fail "PRD missing ## Success Criteria"
grep -Eq "^- \[" "$PRD" || fail "PRD has no checkbox items in Success Criteria or NFRs"

[ -d "$STORIES_DIR" ] || fail "missing $STORIES_DIR"
mapfile -t stories < <(find "$STORIES_DIR" -maxdepth 1 -name 'US-*.md' | sort)
[ "${#stories[@]}" -gt 0 ] || fail "no US-*.md stories found"

max_stories=$(hardcap max_user_stories_per_discover_run)
[ "${#stories[@]}" -le "$max_stories" ] \
  || fail "story count ${#stories[@]} exceeds hardcap $max_stories"

for story in "${stories[@]}"; do
  base=$(basename "$story" .md)

  has_frontmatter_field "$story" "id" || fail "$story missing 'id' in frontmatter"
  has_frontmatter_field "$story" "references" || fail "$story missing 'references' in frontmatter"

  for field in "^## Acceptance Criteria" '\*\*Role\*\*' '\*\*Want\*\*' '\*\*So that\*\*'; do
    grep -Eq "$field" "$story" || fail "$story missing '$field'"
  done

  feature="$FEATURES_DIR/${base}.feature"
  [ -f "$feature" ] || fail "missing $feature (must be 1:1 with $story)"

  require_approved "$story"
  require_approved "$feature"
done

pass

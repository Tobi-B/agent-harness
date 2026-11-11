#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh architect.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="architect"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

ADR_DIR="$DOCS_DIR/adrs"
ARCH="$DOCS_DIR/architecture.md"

require_gate_passed discover

[ -d "$ADR_DIR" ] || fail "missing $ADR_DIR"
# Project ADRs only; meta-*.md (workflow changes) are exempt from the hardcap.
mapfile -t adrs < <(find "$ADR_DIR" -maxdepth 1 -name '000*.md' | sort)
[ "${#adrs[@]}" -gt 0 ] || fail "no 000*.md ADRs found"

max_adrs=$(hardcap max_adrs_v0)
[ "${#adrs[@]}" -le "$max_adrs" ] || fail "ADR count ${#adrs[@]} exceeds hardcap $max_adrs"

for adr in "${adrs[@]}"; do
  has_frontmatter_field "$adr" "id" || fail "$adr missing 'id' in frontmatter"

  status=$(frontmatter_value "$adr" "status")
  [ "$status" = "accepted" ] || fail "$adr status is '$status', expected 'accepted'"

  for section in "## Context and Problem Statement" "## Decision Drivers" "## Considered Options" "## Decision Outcome"; do
    grep -qF "$section" "$adr" || fail "$adr missing MADR section: $section"
  done
done

[ -f "$ARCH" ] || fail "missing $ARCH"
for section in "## Context (Level 1)" "## Containers (Level 2)" "## Components (Level 3)" "## Code (Level 4)" "## Cross-Cutting Concerns"; do
  grep -qF "$section" "$ARCH" || fail "architecture.md missing section: $section"
done

# Approvals last (exit 3): every structural check above has passed.
require_approved "${adrs[@]}"

pass

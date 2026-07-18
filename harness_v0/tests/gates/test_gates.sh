#!/usr/bin/env bash
# Self-tests for the harness gates. Runs against a throwaway fixture harness
# (HARNESS_ROOT override) so the real status.yaml is never touched.
#
# Usage: bash harness_v0/tests/gates/test_gates.sh
set -euo pipefail

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../gates" && pwd)"
REAL_ROOT="$(cd "$GATES_DIR/.." && pwd)"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
export HARNESS_ROOT="$FIXTURE"

failures=0
t() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}
t_fails() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "FAIL $name (expected non-zero exit)"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

# --- fixture setup -----------------------------------------------------------

cp "$REAL_ROOT/workflow.yaml" "$FIXTURE/workflow.yaml"
cp "$REAL_ROOT/status.yaml" "$FIXTURE/status.yaml"
mkdir -p "$FIXTURE/docs/user_stories" "$FIXTURE/tests/features"

cat > "$FIXTURE/docs/prd.md" <<'EOF'
# PRD
## Goals
- goal
## Success Criteria
- [ ] criterion one
## Non-Functional Requirements
- [ ] nfr one
EOF

cat > "$FIXTURE/docs/user_stories/US-001-test.md" <<'EOF'
---
id: US-001
status: draft
references:
  - PRD §Goals
---
# US-001 Test

**Role**: tester
**Want**: a check
**So that**: gates work

## Acceptance Criteria

- [ ] it passes
EOF

cat > "$FIXTURE/tests/features/US-001-test.feature" <<'EOF'
@US-001
Feature: Test
  Scenario: it passes
    Given a fixture
    When the gate runs
    Then it passes
EOF

# --- _lib unit tests ---------------------------------------------------------

# shellcheck source=/dev/null
GATE_NAME="test" . "$GATES_DIR/_lib.sh"

# Regression: awk `exit 0` in a rule still runs END; END's exit must not
# override a successful match (the v1 bug made this always return 1).
t    "has_frontmatter_field finds existing field"  has_frontmatter_field "$FIXTURE/docs/user_stories/US-001-test.md" "id"
t_fails "has_frontmatter_field rejects missing field" has_frontmatter_field "$FIXTURE/docs/user_stories/US-001-test.md" "nope"
t    "frontmatter_value extracts value" test "$(frontmatter_value "$FIXTURE/docs/user_stories/US-001-test.md" "status")" = "draft"

# --- sign-off registry -------------------------------------------------------

t_fails "discover fails without sign-off" bash "$GATES_DIR/discover.sh"

t "signoff.sh records story"   bash "$GATES_DIR/signoff.sh" docs/user_stories/US-001-test.md --by tester
t "signoff.sh records feature" bash "$GATES_DIR/signoff.sh" tests/features/US-001-test.feature --by tester

t "discover passes with valid sign-offs" bash "$GATES_DIR/discover.sh"

echo "tampered" >> "$FIXTURE/docs/user_stories/US-001-test.md"
t_fails "discover fails after post-sign-off edit (hash mismatch)" bash "$GATES_DIR/discover.sh"
bash "$GATES_DIR/signoff.sh" docs/user_stories/US-001-test.md --by tester >/dev/null
t "discover passes after re-sign-off" bash "$GATES_DIR/discover.sh"

# --- gates are pure ----------------------------------------------------------

phase_before=$(yq '.current_phase' "$FIXTURE/status.yaml")
bash "$GATES_DIR/discover.sh" >/dev/null
phase_after=$(yq '.current_phase' "$FIXTURE/status.yaml")
gate_flag=$(yq '.phases.discover.gate_passed' "$FIXTURE/status.yaml")
t "gate run mutates no state" test "$phase_before" = "$phase_after" -a "$gate_flag" = "false"

# --- prerequisite enforcement ------------------------------------------------

t_fails "architect fails while discover gate not passed" bash "$GATES_DIR/architect.sh"

# --- advance.sh --------------------------------------------------------------

t_fails "advance without --yes fails non-interactively" bash "$GATES_DIR/advance.sh" discover < /dev/null
t "advance --yes passes gate and advances" bash "$GATES_DIR/advance.sh" discover --yes
t "advance set gate_passed=true" test "$(yq '.phases.discover.gate_passed' "$FIXTURE/status.yaml")" = "true"
t "advance moved current_phase to architect" test "$(yq '.current_phase' "$FIXTURE/status.yaml")" = "architect"
t "advance wrote audit file" test -n "$(find "$FIXTURE/audit" -name 'discover-*.md' -print -quit 2>/dev/null)"
t_fails "advance rejects unknown phase" bash "$GATES_DIR/advance.sh" bogus --yes

# --- verify gate checkbox logic ---------------------------------------------

for p in architect model implement; do
  yq -i ".phases.$p.gate_passed = true" "$FIXTURE/status.yaml"
done
cat > "$FIXTURE/docs/verify-report.md" <<'EOF'
# Verification
## Result
ok
## Success Criteria
met
## NFR
met
EOF
t_fails "verify fails on unchecked PRD boxes" bash "$GATES_DIR/verify.sh"
sed -i 's/- \[ \]/- [x]/' "$FIXTURE/docs/prd.md"
t "verify passes with all boxes checked" bash "$GATES_DIR/verify.sh"

# -----------------------------------------------------------------------------

echo
if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures test(s) failed"
  exit 1
fi
echo "RESULT: all tests passed"

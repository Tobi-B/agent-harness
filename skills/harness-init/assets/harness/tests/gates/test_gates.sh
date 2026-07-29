#!/usr/bin/env bash
# Self-tests for the harness gates. Runs against a throwaway fixture harness
# (HARNESS_ROOT override) so the real status.yaml is never touched.
#
# Usage: bash harness/tests/gates/test_gates.sh
set -euo pipefail

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../gates" && pwd)"
REAL_ROOT="$(cd "$GATES_DIR/.." && pwd)"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
export HARNESS_ROOT="$FIXTURE"
# The fixture has no src/ and no test tooling; iteration gates must not fail
# on absent pytest/behave. Tool-strictness itself is tested explicitly below.
export HARNESS_ALLOW_MISSING_TOOLS=1

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

signoff() { bash "$GATES_DIR/signoff.sh" "$1" --by tester >/dev/null; }
advance() { bash "$GATES_DIR/advance.sh" "$1" --yes >/dev/null; }
status()  { yq "$1" "$FIXTURE/status.yaml"; }

# --- fixture setup -----------------------------------------------------------

cp "$REAL_ROOT/workflow.yaml" "$FIXTURE/workflow.yaml"
cp "$REAL_ROOT/status.yaml" "$FIXTURE/status.yaml"
mkdir -p "$FIXTURE/docs/user_stories" "$FIXTURE/docs/uml" \
         "$FIXTURE/docs/adrs" "$FIXTURE/docs/iterations" "$FIXTURE/tests/features"

cat > "$FIXTURE/docs/prd.md" <<'EOF'
# PRD
## Goals
- goal
## Success Criteria
- [ ] criterion one
## Non-Functional Requirements
- [ ] nfr one
EOF

make_story() {
  local id="$1"
  cat > "$FIXTURE/docs/user_stories/${id}-test.md" <<EOF
---
id: $id
status: draft
references:
  - PRD §Goals
---
# $id Test

**Role**: tester
**Want**: a check
**So that**: gates work

## Acceptance Criteria

- [ ] it passes
EOF
  cat > "$FIXTURE/tests/features/${id}-test.feature" <<EOF
@$id
Feature: $id
  Scenario: it passes
    Given a fixture
    When the gate runs
    Then it passes
EOF
  signoff "docs/user_stories/${id}-test.md"
  signoff "tests/features/${id}-test.feature"
}

# --- _lib unit tests ---------------------------------------------------------

# shellcheck source=../../gates/_lib.sh
GATE_NAME="test" . "$GATES_DIR/_lib.sh"

make_story US-001

# Regression: awk `exit 0` in a rule still runs END; END's exit must not
# override a successful match (the v1 bug made this always return 1).
t       "has_frontmatter_field finds existing field"  has_frontmatter_field "$FIXTURE/docs/user_stories/US-001-test.md" "id"
t_fails "has_frontmatter_field rejects missing field" has_frontmatter_field "$FIXTURE/docs/user_stories/US-001-test.md" "nope"
t       "frontmatter_value extracts value" test "$(frontmatter_value "$FIXTURE/docs/user_stories/US-001-test.md" "status")" = "draft"

# --- discover: sign-off registry --------------------------------------------

t "discover passes with valid sign-offs" bash "$GATES_DIR/discover.sh"

echo "tampered" >> "$FIXTURE/docs/user_stories/US-001-test.md"
t_fails "discover fails after post-sign-off edit (hash mismatch)" bash "$GATES_DIR/discover.sh"
signoff "docs/user_stories/US-001-test.md"
t "discover passes after re-sign-off" bash "$GATES_DIR/discover.sh"

# --- gates are pure ----------------------------------------------------------

phase_before=$(status '.current_phase')
bash "$GATES_DIR/discover.sh" >/dev/null
t "gate run mutates no state" \
  test "$phase_before" = "$(status '.current_phase')" -a "$(status '.phases.discover.gate_passed')" = "false"

# --- prerequisite enforcement + advance --------------------------------------

t_fails "architect fails while discover gate not passed" bash "$GATES_DIR/architect.sh"
t_fails "advance without --yes fails non-interactively" bash "$GATES_DIR/advance.sh" discover < /dev/null
t_fails "advance rejects unknown phase" bash "$GATES_DIR/advance.sh" bogus --yes

t "advance discover" advance discover
t "discover gate_passed recorded" test "$(status '.phases.discover.gate_passed')" = "true"
t "current_phase is architect"     test "$(status '.current_phase')" = "architect"
t "audit file written"             test -n "$(find "$FIXTURE/audit" -name 'discover-*.md' -print -quit)"

# --- architect ---------------------------------------------------------------

cat > "$FIXTURE/docs/adrs/0001-test.md" <<'EOF'
---
id: 0001
status: accepted
---
# 0001 Test
## Context and Problem Statement
x
## Decision Drivers
- d
## Considered Options
1. A
2. B
## Decision Outcome
A
EOF
cat > "$FIXTURE/docs/architecture.md" <<'EOF'
# Architecture
## Context (Level 1)
[Context diagram](uml/c4-context.mmd)
## Containers (Level 2)
[Container diagram](uml/c4-container.mmd)
## Components (Level 3)
[Component diagram](uml/c4-component.mmd)
## Code (Level 4)
## Cross-Cutting Concerns
EOF
t_fails "architect fails without ADR sign-off" bash "$GATES_DIR/architect.sh"
signoff "docs/adrs/0001-test.md"
t "advance architect" advance architect

# --- model -------------------------------------------------------------------

for d in c4-context c4-container c4-component; do
  printf '%%%% sources: US-001, ADR-0001\nflowchart LR\n  A-->B\n' > "$FIXTURE/docs/uml/$d.mmd"
done
printf 'sequenceDiagram\n  A->>B: x\n' > "$FIXTURE/docs/uml/sequence-flow.mmd"
t_fails "model fails when a diagram has no sources line" bash "$GATES_DIR/model.sh"
printf '%%%% sources: US-001\nsequenceDiagram\n  A->>B: x\n' > "$FIXTURE/docs/uml/sequence-flow.mmd"
printf '%%%% sources: US-001\nstateDiagram-v2\n  [*] --> Idle\n' > "$FIXTURE/docs/uml/state-life.mmd"
t "advance model" advance model

# --- plan --------------------------------------------------------------------

make_story US-002

write_plan() {
  cat > "$FIXTURE/docs/plan.md" <<EOF
---
iterations:
$1
---
# Plan
EOF
}

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001]"
t_fails "plan fails when a story is in no iteration" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001, US-999]
  - id: ITER-02
    goal: second
    stories: [US-002]"
t_fails "plan fails on unknown story reference" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001]
  - id: ITER-01
    goal: dup
    stories: [US-002]"
t_fails "plan fails on duplicate iteration id" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001]
  - id: ITER-02
    goal: second
    stories: [US-002]"
t_fails "plan fails without sign-off" bash "$GATES_DIR/plan.sh"
signoff "docs/plan.md"
t "advance plan" advance plan
t "plan opened iteration cycle at ITER-01" test "$(status '.current_iteration')" = "ITER-01"
t "current_phase is design"                test "$(status '.current_phase')" = "design"

# --- design (iteration-scoped) ----------------------------------------------

make_design() {
  local iter="$1" stories="$2"
  cat > "$FIXTURE/docs/iterations/${iter}.md" <<EOF
---
id: $iter
---
# $iter
Covers stories: $stories
## Goal
g
## Approach
\`\`\`mermaid
sequenceDiagram
  A->>B: x
\`\`\`
## Affected Components
c
## Test Strategy
t
## Verification
- [ ] $stories pending
EOF
}

# Stand-in for the mermaid-render skill: what design.sh actually requires is a
# render carrying the source's sha256 (see gates/design.sh).
render_design() {
  local iter="$1"
  printf '<html><meta name="rendered-from" data-sha256="%s"></html>' \
    "$(sha256_of "$FIXTURE/docs/iterations/${iter}.md")" \
    > "$FIXTURE/docs/iterations/${iter}.html"
}

make_design ITER-01 US-001
t_fails "design fails without rendered html" bash "$GATES_DIR/design.sh"

render_design ITER-01
echo "<!-- edited after render -->" >> "$FIXTURE/docs/iterations/ITER-01.md"
t_fails "design fails on stale render (source changed)" bash "$GATES_DIR/design.sh"

render_design ITER-01
t_fails "design fails without sign-off" bash "$GATES_DIR/design.sh"
signoff "docs/iterations/ITER-01.md"
t "design passes with fresh render + sign-off" bash "$GATES_DIR/design.sh"

t_fails "implement blocked before design gate passes" bash "$GATES_DIR/implement.sh"
t "advance design" advance design
t "current_phase is implement" test "$(status '.current_phase')" = "implement"
t "design flag under iteration" test "$(status '.iterations.ITER-01.design.gate_passed')" = "true"

# --- implement + verify (iteration-scoped) ----------------------------------

t "advance implement" advance implement
t_fails "verify fails with unchecked items" bash "$GATES_DIR/verify.sh"

sed -i 's/- \[ \] US-001 pending/- [x] US-001 verified/' "$FIXTURE/docs/iterations/ITER-01.md"
t "verify passes when all items checked" bash "$GATES_DIR/verify.sh"

# --- THE LOOP: verify → next iteration --------------------------------------

t "advance verify (ITER-01)" advance verify
t "looped back to design"           test "$(status '.current_phase')" = "design"
t "current_iteration is now ITER-02" test "$(status '.current_iteration')" = "ITER-02"
t "ITER-01 verify recorded"          test "$(status '.iterations.ITER-01.verify.gate_passed')" = "true"

t_fails "release blocked while ITER-02 unfinished" bash "$GATES_DIR/release.sh"

# Second iteration through the cycle.
make_design ITER-02 US-002
render_design ITER-02
signoff "docs/iterations/ITER-02.md"
t "advance design (ITER-02)"    advance design
t "advance implement (ITER-02)" advance implement
sed -i 's/- \[ \] US-002 pending/- [x] US-002 verified/' "$FIXTURE/docs/iterations/ITER-02.md"
t "advance verify (ITER-02)" advance verify

# --- cycle closes into release ----------------------------------------------

t "last iteration exits the loop" test "$(status '.current_phase')" = "release"
t "current_iteration cleared"     test "$(status '.current_iteration')" = "null"

cat > "$FIXTURE/docs/verify-report.md" <<'EOF'
# Verification
## Result
ok
## Success Criteria
met
## NFR
met
EOF
t_fails "release fails on unchecked PRD boxes" bash "$GATES_DIR/release.sh"
sed -i 's/- \[ \]/- [x]/' "$FIXTURE/docs/prd.md"
t "release passes with all boxes checked" bash "$GATES_DIR/release.sh"
t "advance release" advance release
t "workflow complete" test "$(status '.phases.release.gate_passed')" = "true"

# --- autopilot (meta-0003) ---------------------------------------------------
#
# The fixture has walked to the end, so these run against a finished project:
# what matters here is who may flip the switch and what the switch permits, not
# the phase machine, which the loop tests above already cover.

autopilot() { bash "$GATES_DIR/autopilot.sh" "$@"; }
autopilot_on() {
  HARNESS_AUTOPILOT_I_AM_HUMAN=1 autopilot on "$@" --by tester >/dev/null
}

t_fails "autopilot is off in a fresh harness" autopilot status
t_fails "autopilot cannot be enabled without a terminal" \
  env -u HARNESS_AUTOPILOT_I_AM_HUMAN HARNESS_ROOT="$FIXTURE" \
      bash "$GATES_DIR/autopilot.sh" on < /dev/null
t_fails "autopilot rejects an unreadable --expires" \
  env HARNESS_AUTOPILOT_I_AM_HUMAN=1 HARNESS_ROOT="$FIXTURE" \
      bash "$GATES_DIR/autopilot.sh" on --expires 9x
t_fails "autopilot caps --expires at 3d" \
  env HARNESS_AUTOPILOT_I_AM_HUMAN=1 HARNESS_ROOT="$FIXTURE" \
      bash "$GATES_DIR/autopilot.sh" on --expires 7d
t_fails "autopilot rejects a zero iteration budget" \
  env HARNESS_AUTOPILOT_I_AM_HUMAN=1 HARNESS_ROOT="$FIXTURE" \
      bash "$GATES_DIR/autopilot.sh" on --max-iterations 0

t "autopilot turns on" autopilot_on --expires 4h --max-iterations 2
t "autopilot reports on" autopilot status
t "autopilot records who enabled it" test "$(status '.autopilot.enabled_by')" = "tester"

mkdir -p "$FIXTURE/docs/iterations"
echo "# ITER-99 autopilot fixture" > "$FIXTURE/docs/iterations/ITER-99.md"

t "auto sign-off accepts an iteration artifact" \
  bash "$GATES_DIR/signoff.sh" docs/iterations/ITER-99.md --auto
t "auto sign-off is marked auto:true" \
  test "$(status '.signed_off_artifacts[] | select(.path == "docs/iterations/ITER-99.md") | .auto')" = "true"
t "auto sign-off is attributed to autopilot" \
  bash -c "status() { yq \"\$1\" \"$FIXTURE/status.yaml\"; }; \
           status '.signed_off_artifacts[] | select(.path == \"docs/iterations/ITER-99.md\") | .by' \
           | grep -q '^autopilot('"
t_fails "auto sign-off refuses a non-iteration artifact" \
  bash "$GATES_DIR/signoff.sh" docs/prd.md --auto

# Budget: charged once per iteration, no matter how many phases it carries.
. "$GATES_DIR/_lib.sh"
t "budget charges an iteration once" bash -c "
  . '$GATES_DIR/_lib.sh'
  autopilot_claim_iteration ITER-98
  autopilot_claim_iteration ITER-98
  [ \"\$(yq '.autopilot.iterations_used' '$FIXTURE/status.yaml')\" = '1' ]"
t "budget charges a second iteration separately" bash -c "
  . '$GATES_DIR/_lib.sh'
  autopilot_claim_iteration ITER-97
  [ \"\$(yq '.autopilot.iterations_used' '$FIXTURE/status.yaml')\" = '2' ]"
t_fails "autopilot stops when the iteration budget is spent" autopilot status
t_fails "auto sign-off refused once out of budget" \
  bash "$GATES_DIR/signoff.sh" docs/iterations/ITER-99.md --auto

t "autopilot turns on again with fresh budget" autopilot_on --expires 4h --max-iterations 1
yq -i '.autopilot.expires_at = "2020-01-01T00:00:00Z"' "$FIXTURE/status.yaml"
t_fails "autopilot stops when expired" autopilot status
t_fails "auto sign-off refused once expired" \
  bash "$GATES_DIR/signoff.sh" docs/iterations/ITER-99.md --auto

t "autopilot turns off" autopilot off
t "off is recorded" test "$(status '.autopilot.enabled')" = "false"
t_fails "advance still needs a human when autopilot is off" \
  bash "$GATES_DIR/advance.sh" discover < /dev/null

# --- tool strictness ---------------------------------------------------------

t_fails "implement fails on missing tools without opt-out" \
  env HARNESS_ALLOW_MISSING_TOOLS=0 PATH="/usr/bin:/bin" \
      HARNESS_ROOT="$FIXTURE" bash "$GATES_DIR/implement.sh"

# -----------------------------------------------------------------------------

echo
if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures test(s) failed"
  exit 1
fi
echo "RESULT: all tests passed"

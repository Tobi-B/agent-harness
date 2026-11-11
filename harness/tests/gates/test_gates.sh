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
# Project root of the fixture: never let gates scan the real parent of $FIXTURE.
export HARNESS_PROJECT_ROOT="$FIXTURE/project"
mkdir -p "$HARNESS_PROJECT_ROOT"

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
# t_msg: expect failure AND a specific message. A gate has many reasons to
# exit non-zero, so a bare t_fails passes just as happily when something
# unrelated broke first: a phase that is not current, a diagram that is not
# there yet, a tool missing from a trimmed PATH. Use this wherever more than
# one check could be the one that fails.
t_msg() {
  local name="$1" pattern="$2"; shift 2
  local out
  if out=$("$@" 2>&1); then
    echo "FAIL $name (expected non-zero exit)"; failures=$((failures + 1))
  elif grep -q -- "$pattern" <<<"$out"; then
    echo "ok   $name"
  else
    echo "FAIL $name (wrong reason: $(tail -1 <<<"$out"))"; failures=$((failures + 1))
  fi
}

# Write the approval marker the way the agent would after the user approves:
# frontmatter field in .md artifacts, comment line in .feature files.
approve() {
  local f="$FIXTURE/$1"
  case "$f" in
    *.feature)
      if grep -q '^#[[:space:]]*approved_by:' "$f"; then
        sed -i 's/^#[[:space:]]*approved_by:.*/# approved_by: user/' "$f"
      else
        sed -i '1i # approved_by: user' "$f"
      fi ;;
    *)
      if grep -q '^approved_by:' "$f"; then
        sed -i 's/^approved_by:.*/approved_by: user/' "$f"
      else
        sed -i '0,/^---$/s/^---$/---\napproved_by: user/' "$f"
      fi ;;
  esac
}
unapprove() { sed -i '/^#\{0,1\}[[:space:]]*approved_by:/d' "$FIXTURE/$1"; }
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
  approve "docs/user_stories/${id}-test.md"
  approve "tests/features/${id}-test.feature"
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
t       "approved_by_of reads frontmatter marker" \
  test "$(approved_by_of "$FIXTURE/docs/user_stories/US-001-test.md")" = "user"
t       "approved_by_of reads feature comment marker" \
  test "$(approved_by_of "$FIXTURE/tests/features/US-001-test.feature")" = "user"

# v7: only 'user' / 'autopilot' count. Drafts and placeholders must NOT pass —
# the story template itself ships 'approved_by:   # left empty in drafts ...'.
# Subshell: require_approved calls fail(), which exits — not our test shell.
approved() { ( require_approved "$1" ); }
approval_fixture() { printf -- '---\nid: X\napproved_by: %s\n---\n' "$1" > "$FIXTURE/appr.md"; }
for v in '' '""' 'TBD' 'pending' 'no' "            # left empty in drafts; the agent writes 'user' after approval in chat"; do
  approval_fixture "$v"
  t_fails "require_approved rejects placeholder [${v:0:20}]" approved "$FIXTURE/appr.md"
done
for v in 'user' 'autopilot' '"user"' 'user (2026-09-21)' 'user  # approved in chat'; do
  approval_fixture "$v"
  t "require_approved accepts [${v}]" approved "$FIXTURE/appr.md"
done
# A '# approved_by:' line counts only in .feature files, not in markdown bodies.
# shellcheck disable=SC2016  # literal backticks: a fenced code block
printf -- '---\nid: X\n---\n```\n# approved_by: user\n```\n' > "$FIXTURE/appr.md"
t_fails "comment marker ignored outside .feature files" approved "$FIXTURE/appr.md"
# Windows checkout: CRLF must not hide a marker.
printf -- '---\r\nid: X\r\napproved_by: user\r\n---\r\n' > "$FIXTURE/appr.md"
t "CRLF frontmatter marker is read" approved "$FIXTURE/appr.md"
printf -- '# approved_by: user\r\nFeature: x\r\n' > "$FIXTURE/appr.feature"
t "CRLF feature marker is read" approved "$FIXTURE/appr.feature"
rm -f "$FIXTURE/appr.md" "$FIXTURE/appr.feature"
t "rel_to_root is portable" test "$(rel_to_root "$FIXTURE/docs/x.md")" = "docs/x.md"

# --- discover: approval markers ----------------------------------------------

t "discover passes with approval markers" bash "$GATES_DIR/discover.sh"

unapprove "docs/user_stories/US-001-test.md"
t_msg "discover fails when a story lacks approved_by" "is not approved" bash "$GATES_DIR/discover.sh"
approve "docs/user_stories/US-001-test.md"
t "discover passes once the marker is restored" bash "$GATES_DIR/discover.sh"

# No hash, by design (meta-0004): a post-approval edit does not invalidate the
# marker mechanically — re-asking the user on material edits is an instruction.
echo "tampered" >> "$FIXTURE/docs/user_stories/US-001-test.md"
t "discover still passes after a post-approval edit (trust model)" bash "$GATES_DIR/discover.sh"

# --- gates are pure ----------------------------------------------------------

phase_before=$(status '.current_phase')
bash "$GATES_DIR/discover.sh" >/dev/null
t "gate run mutates no state" \
  test "$phase_before" = "$(status '.current_phase')" -a "$(status '.phases.discover.gate_passed')" = "false"

# --- prerequisite enforcement + advance --------------------------------------

t_msg "architect fails while discover gate not passed" "prerequisite phase 'discover'" bash "$GATES_DIR/architect.sh"
t_msg "advance without --yes fails non-interactively" "phase transitions require user approval" \
  bash "$GATES_DIR/advance.sh" discover < /dev/null
t_msg "advance rejects unknown phase" "unknown phase 'bogus'" bash "$GATES_DIR/advance.sh" bogus --yes

t "advance discover" advance discover
t "discover gate_passed recorded" test "$(status '.phases.discover.gate_passed')" = "true"
t "current_phase is architect"     test "$(status '.current_phase')" = "architect"
t "audit file written"             test -n "$(find "$FIXTURE/audit" -name 'discover-*.md' -print -quit)"

t_msg "advance refuses a later phase" "is not the current phase" advance model
# An earlier phase is refused for the same reason — it is not current. The
# separate "already passed" guard is only reachable once the workflow is
# finished, and is tested there.
t_msg "advance refuses an earlier phase that already passed" "is not the current phase" advance discover
t "refused advance left the phase alone" test "$(status '.current_phase')" = "architect"

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
t_msg "architect fails without ADR approval" "is not approved" bash "$GATES_DIR/architect.sh"
approve "docs/adrs/0001-test.md"
t "advance architect" advance architect

# --- model -------------------------------------------------------------------

for d in c4-context c4-container c4-component; do
  printf '%%%% sources: US-001, ADR-0001\nflowchart LR\n  A-->B\n' > "$FIXTURE/docs/uml/$d.mmd"
done
printf 'sequenceDiagram\n  A->>B: x\n' > "$FIXTURE/docs/uml/sequence-flow.mmd"
t_msg "model fails without a state diagram" "no state-" bash "$GATES_DIR/model.sh"
# The state diagram has to exist before a missing sources line can be the
# reason: model.sh looks for the diagram first, and the sources test used to
# pass on its absence alone.
printf '%%%% sources: US-001\nstateDiagram-v2\n  [*] --> Idle\n' > "$FIXTURE/docs/uml/state-life.mmd"
t_msg "model fails when a diagram has no sources line" "missing '%% sources:'" bash "$GATES_DIR/model.sh"
printf '%%%% sources: US-001\nsequenceDiagram\n  A->>B: x\n' > "$FIXTURE/docs/uml/sequence-flow.mmd"
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
t_msg "plan fails when a story is in no iteration" "is not covered by any iteration" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001, US-999]
  - id: ITER-02
    goal: second
    stories: [US-002]"
t_msg "plan fails on unknown story reference" "references story 'US-999'" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001]
  - id: ITER-01
    goal: dup
    stories: [US-002]"
t_msg "plan fails on duplicate iteration id" "duplicate iteration id" bash "$GATES_DIR/plan.sh"

write_plan "  - id: ITER-01
    goal: first
    stories: [US-001]
  - id: ITER-02
    goal: second
    stories: [US-002]"
t_msg "plan fails without approval" "is not approved" bash "$GATES_DIR/plan.sh"
approve "docs/plan.md"
# v7 regression: first_iteration_id used `| head -1` under pipefail and died
# with SIGPIPE (exit 141) in ~40% of calls. One call proves nothing; 50 do.
t "first_iteration_id is stable under pipefail (50 calls)" bash -c "
  . '$GATES_DIR/_lib.sh'
  for i in \$(seq 1 50); do [ \"\$(first_iteration_id)\" = ITER-01 ] || exit 1; done"
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
# rendered html that is not older than its source (mtime, see gates/design.sh).
render_design() {
  local iter="$1"
  printf '<html>render</html>' > "$FIXTURE/docs/iterations/${iter}.html"
}

make_design ITER-01 US-001
t_msg "design fails without rendered html" "missing rendered" bash "$GATES_DIR/design.sh"

render_design ITER-01
# Age the render explicitly: same-second edits are deliberately tolerated, so
# staleness needs an html that is measurably older than the markdown.
touch -d "2000-01-01 00:00:00" "$FIXTURE/docs/iterations/ITER-01.html"
t_msg "design fails on stale render (older than source)" "stale render" bash "$GATES_DIR/design.sh"

render_design ITER-01
t_msg "design fails without approval" "is not approved" bash "$GATES_DIR/design.sh"
approve "docs/iterations/ITER-01.md"
render_design ITER-01
t "design passes with fresh render + approval" bash "$GATES_DIR/design.sh"

t_msg "implement blocked before design gate passes" "has not passed its 'design' gate" bash "$GATES_DIR/implement.sh"
t "advance design" advance design
t "current_phase is implement" test "$(status '.current_phase')" = "implement"
t "design flag under iteration" test "$(status '.iterations.ITER-01.design.gate_passed')" = "true"

# --- implement + verify (iteration-scoped) ----------------------------------

t "advance implement" advance implement
t_msg "verify fails with unchecked items" "unchecked" bash "$GATES_DIR/verify.sh"

sed -i 's/- \[ \] US-001 pending/- [x] US-001 verified/' "$FIXTURE/docs/iterations/ITER-01.md"
t "verify passes when all items checked" bash "$GATES_DIR/verify.sh"

# --- THE LOOP: verify → next iteration --------------------------------------

t "advance verify (ITER-01)" advance verify
t "looped back to design"           test "$(status '.current_phase')" = "design"
t "current_iteration is now ITER-02" test "$(status '.current_iteration')" = "ITER-02"
t "ITER-01 verify recorded"          test "$(status '.iterations.ITER-01.verify.gate_passed')" = "true"

t_msg "release blocked while ITER-02 unfinished" "cannot release" bash "$GATES_DIR/release.sh"

# Second iteration through the cycle.
make_design ITER-02 US-002
approve "docs/iterations/ITER-02.md"
render_design ITER-02
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
t_msg "release fails on unchecked PRD boxes" "PRD has no checked" bash "$GATES_DIR/release.sh"
sed -i 's/- \[ \]/- [x]/' "$FIXTURE/docs/prd.md"
t "release passes with all boxes checked" bash "$GATES_DIR/release.sh"
t "advance release" advance release
t "workflow complete" test "$(status '.phases.release.gate_passed')" = "true"
# The one state in which a once-phase is both current and passed: the workflow
# is finished. This is the guard that an interrupted advance would also hit.
t_msg "a finished workflow cannot be advanced again" "already passed its gate" advance release

# --- autopilot (meta-0003) ---------------------------------------------------
#
# The fixture has walked to the end, so these run against a finished project:
# what matters here is who may flip the switch and what the switch permits, not
# the phase machine, which the loop tests above already cover.

autopilot() { bash "$GATES_DIR/autopilot.sh" "$@"; }
autopilot_on() { autopilot on "$@" --by tester >/dev/null; }

t_fails "autopilot is off in a fresh harness" autopilot status
# Enabling is chat-instructed: no terminal needed (meta-0005). The rule that
# the agent runs 'on' only on explicit user instruction is an instruction.
t "autopilot enables without a terminal" \
  bash -c "bash '$GATES_DIR/autopilot.sh' on --by tester < /dev/null > /dev/null"
t "autopilot turns off again" autopilot off
t_fails "autopilot rejects an unreadable --expires" autopilot on --expires 9x
t_fails "autopilot caps --expires at 3d" autopilot on --expires 7d
t_fails "autopilot rejects a zero iteration budget" autopilot on --max-iterations 0

# Scope: everything except release (meta-0005).
t "auto scope covers discover" \
  bash -c ". '$GATES_DIR/_lib.sh'; autopilot_phase_in_scope discover"
t "auto scope covers plan" \
  bash -c ". '$GATES_DIR/_lib.sh'; autopilot_phase_in_scope plan"
t_fails "auto scope excludes release" \
  bash -c ". '$GATES_DIR/_lib.sh'; autopilot_phase_in_scope release"

t "autopilot turns on" autopilot_on --expires 4h --max-iterations 2
t "autopilot reports on" autopilot status
t "autopilot records who enabled it" test "$(status '.autopilot.enabled_by')" = "tester"

# Budget: charged once per iteration, no matter how many phases it carries.
# shellcheck source=../../gates/_lib.sh
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

t "autopilot turns on again with fresh budget" autopilot_on --expires 4h --max-iterations 1
yq -i '.autopilot.expires_at = "2020-01-01T00:00:00Z"' "$FIXTURE/status.yaml"
t_fails "autopilot stops when expired" autopilot status

t "autopilot turns off" autopilot off
t "off is recorded" test "$(status '.autopilot.enabled')" = "false"

# --- autopilot end to end: a real walk through advance.sh ---------------------
#
# Everything above checks the switch and the budget arithmetic by calling
# library functions. None of it sends advance.sh down its autopilot branch, and
# the two tests that claimed to ("release still needs a human while autopilot
# is on", "advance still needs a human when autopilot is off") failed for an
# unrelated reason: release had already passed, discover was not current.
# Rewind the fixture to the start of ITER-02 and walk it the way an unattended
# agent would: no --yes, no terminal.

auto_advance() { bash "$GATES_DIR/advance.sh" "$1" < /dev/null; }

yq -i '.current_phase = "design" | .current_iteration = "ITER-02"
       | .iterations."ITER-02" = {}
       | .phases.release.gate_passed = false | .phases.release.completed_at = null' \
  "$FIXTURE/status.yaml"
render_design ITER-02   # verify edited the markdown after the first render

t_msg "advance needs a human when autopilot is off" "phase transitions require user approval" \
  auto_advance design
t "a refused advance changes nothing" \
  test "$(status '.current_phase')" = "design" \
    -a "$(status '.iterations.ITER-02.design.gate_passed // false')" = "false"

autopilot_on --expires 4h --max-iterations 1
t "autopilot advances design without a prompt" auto_advance design
t "auto-advance records the gate"      test "$(status '.iterations.ITER-02.design.gate_passed')" = "true"
t "auto-advance moves to implement"    test "$(status '.current_phase')" = "implement"
t "auto-advance charges the iteration" test "$(status '.autopilot.iterations_used')" = "1"
t "audit attributes the transition to autopilot" \
  grep -q -- 'approved by\*\*: autopilot(tester)' "$FIXTURE"/audit/design-*.md
# The budget is spent now (1 of 1); the iteration it paid for still finishes.
t "a claimed iteration auto-advances implement on a spent budget" auto_advance implement
t "a claimed iteration auto-advances verify on a spent budget"    auto_advance verify
t "the walk charged one iteration, not three phases" test "$(status '.autopilot.iterations_used')" = "1"
t "the last iteration hands over to release"         test "$(status '.current_phase')" = "release"

# Release, with a fresh and fully valid budget: the refusal has to come from
# the scope, not from an autopilot that happens to be exhausted.
autopilot_on --expires 4h --max-iterations 2
t "autopilot is on with budget left" autopilot status
t_msg "release needs a human even while autopilot is on" "phase transitions require user approval" \
  auto_advance release
t "a refused release stays unpassed" test "$(status '.phases.release.gate_passed')" = "false"
t "release advances once the human says so" advance release
autopilot off >/dev/null

# Tool strictness of the implement gate is tested further down, against a
# fixture that reaches the check and with the exact message expected. The test
# that used to sit here trimmed PATH but ran with no current iteration, so it
# passed before the gate ever looked at a tool.

# --- v7: autopilot finishes the iterations it claimed -----------------------

yq -i '.current_phase = "implement" | .current_iteration = "ITER-01"' "$FIXTURE/status.yaml"
autopilot_on --expires 4h --max-iterations 1
t "claimed iteration can finish on a spent budget" bash -c "
  . '$GATES_DIR/_lib.sh'
  autopilot_claim_iteration ITER-01
  autopilot_active_for implement && autopilot_active_for verify"
yq -i '.current_iteration = "ITER-02"' "$FIXTURE/status.yaml"
t_fails "an unclaimed iteration still needs budget" bash -c "
  . '$GATES_DIR/_lib.sh'; autopilot_active_for design"
yq -i '.autopilot.expires_at = "2020-01-01T00:00:00Z"' "$FIXTURE/status.yaml"
yq -i '.current_iteration = "ITER-01"' "$FIXTURE/status.yaml"
t_fails "expiry stops even a claimed iteration" bash -c "
  . '$GATES_DIR/_lib.sh'; autopilot_active_for implement"
autopilot off >/dev/null

# --- v7: implement gate — project root, configured commands, no silent pass --

IMP="$(mktemp -d)"
cp -r "$FIXTURE/." "$IMP/"
yq -i '.current_iteration = "ITER-01" | .iterations.ITER-01.design.gate_passed = true' "$IMP/status.yaml"
IMP_PROJ="$IMP/proj"; mkdir -p "$IMP_PROJ"
imp() { env HARNESS_ROOT="$IMP" HARNESS_PROJECT_ROOT="$IMP_PROJ" HARNESS_ALLOW_MISSING_TOOLS="${ALLOW:-0}" \
          bash "$GATES_DIR/implement.sh"; }
imp_allow() { ALLOW=1 imp; }
cfg() { cat > "$IMP/project.yaml"; }

cfg <<'EOF'
source_dirs: [src]
commands: { test: "", lint: "", acceptance: "" }
EOF
t_msg "implement fails when there is no source" "no source found" imp
mkdir -p "$IMP_PROJ/src"; echo 'int main() { return 0; }' > "$IMP_PROJ/src/main.cpp"
t_msg "implement fails on unconfigured commands (no silent pass)" "no 'test' command configured" imp
t "unconfigured commands pass only with explicit opt-out" imp_allow

cfg <<'EOF'
source_dirs: [src]
commands:
  test: test -f src/main.cpp
  lint: "true"
  acceptance: ls harness_marker_absent_is_fine >/dev/null 2>&1 || true
EOF
t "commands run from the project root and pass" imp

cfg <<'EOF'
source_dirs: [src]
commands: { test: "false", lint: "true", acceptance: "true" }
EOF
t_msg "a failing command fails the gate" "'test' failed" imp
t_msg "a failing command is never downgraded by the opt-out" "'test' failed" imp_allow

cfg <<'EOF'
source_dirs: [src]
commands: { test: "true", lint: "true", acceptance: "true" }
EOF
echo '  x = 1;  // TODO remove' >> "$IMP_PROJ/src/main.cpp"
t_msg "TODO in a comment fails the gate" "TODO/FIXME" imp
echo 'todo_check: false' >> "$IMP/project.yaml"
t "todo_check: false disables the scan" imp
sed -i '/TODO/d' "$IMP_PROJ/src/main.cpp"

cfg <<'EOF'
source_dirs: [src]
commands: { test: "CI=1 true", lint: "true", acceptance: "true" }
EOF
t "leading VAR=value in a command is not mistaken for the tool" imp
cfg <<'EOF'
source_dirs: [src]
commands: { test: "definitely-not-a-tool --run", lint: "true", acceptance: "true" }
EOF
t_msg "missing tool is named in the failure" "needs 'definitely-not-a-tool'" imp
rm -rf "$IMP"

# -----------------------------------------------------------------------------

echo
if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures test(s) failed"
  exit 1
fi
echo "RESULT: all tests passed"

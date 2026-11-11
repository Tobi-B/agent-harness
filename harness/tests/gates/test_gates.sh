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

# t_rc: expect one exact exit code. Gates exit 1 for "work needed" and 3 for
# "only the human's word is missing"; a loop acts on the difference.
t_rc() {
  local name="$1" want="$2" rc=0; shift 2
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $rc, expected $want)"; failures=$((failures + 1))
  fi
}
# t_out: expect success AND a line in the output.
t_out() {
  local name="$1" pattern="$2"; shift 2
  local out
  if ! out=$("$@" 2>&1); then
    echo "FAIL $name (exit non-zero: $(tail -1 <<<"$out"))"; failures=$((failures + 1))
  elif grep -q -- "$pattern" <<<"$out"; then
    echo "ok   $name"
  else
    echo "FAIL $name (output lacks '$pattern')"; failures=$((failures + 1))
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
# 'autopilot' is not in this list any more: since v8 it counts only in auto
# mode full, which is tested with the modes further down.
for v in 'user' '"user"' 'user (2026-09-21)' 'user  # approved in chat'; do
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

# Scope is fixed per mode (meta-0008). build, the default: the iteration cycle
# only. A status file without a mode — every pre-v8 installation — is build.
in_scope() { bash -c ". '$GATES_DIR/_lib.sh'; autopilot_phase_in_scope $1"; }
for ph in design implement verify; do
  t "build carries $ph" in_scope "$ph"
done
for ph in discover architect model plan release; do
  t_fails "build does not carry $ph" in_scope "$ph"
done
yq -i 'del(.autopilot.mode)' "$FIXTURE/status.yaml"
t_fails "a status file without a mode is build: plan is not carried" in_scope plan
yq -i '.autopilot.mode = "full"' "$FIXTURE/status.yaml"
for ph in discover architect model plan design implement verify; do
  t "full carries $ph" in_scope "$ph"
done
t_fails "full does not carry release" in_scope release
yq -i '.autopilot.mode = "build"' "$FIXTURE/status.yaml"
t_fails "autopilot rejects an unknown mode" autopilot on --mode turbo
t_msg "autopilot names an option that lacks its value" "needs a value" autopilot on --expires

t "autopilot turns on" autopilot_on --expires 4h --max-iterations 2
t "autopilot reports on" autopilot status
t "autopilot records who enabled it" test "$(status '.autopilot.enabled_by')" = "tester"
t "autopilot defaults to mode build" test "$(status '.autopilot.mode')" = "build"
t "enabling autopilot leaves an audit entry" \
  grep -q -- 'mode\*\*: build' "$FIXTURE"/audit/autopilot-*.md
t "the dead scope field is gone" test "$(status '.autopilot.scope')" = "null"

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
# v8: a spent budget does not turn `status` off. advance.sh still carries the
# iteration that spent it, and an agent told to stop when status says so used
# to stop after design. What a spent budget does stop is a NEW iteration.
t "autopilot status stays on with a spent budget" autopilot status
t_msg "a spent budget blocks an iteration that was not claimed" "used its budget" \
  bash -c ". '$GATES_DIR/_lib.sh'; autopilot_block_reason design"

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
  grep -q -- 'transition via\*\*: autopilot(build, enabled by tester)' "$FIXTURE"/audit/design-*.md
t "autopilot status stays on while the claimed iteration finishes" autopilot status
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

# =============================================================================
# v8 (meta-0008): decision-gated autonomy
# =============================================================================

rewind() { yq -i "$1" "$FIXTURE/status.yaml"; }
next() { bash "$GATES_DIR/next.sh"; }

autopilot off >/dev/null
rewind '.current_phase = "design" | .current_iteration = "ITER-02"
        | .iterations."ITER-02" = {} | .phases.release.gate_passed = false'

# --- exit 3: only the human's word is missing --------------------------------
#
# A loop has to tell "there is work to do" from "there is nothing left but an
# approval". Gates run every structural check first and exit 3 at the end.

unapprove "docs/iterations/ITER-02.md"
render_design ITER-02
t_rc "design exits 3 when only the approval is missing" 3 bash "$GATES_DIR/design.sh"
touch -d "2000-01-01 00:00:00" "$FIXTURE/docs/iterations/ITER-02.html"
t_rc "design exits 1 on a stale render of an unapproved design" 1 bash "$GATES_DIR/design.sh"
# v7 made every approval force a re-render: writing the marker makes the
# markdown newer than the page the user just looked at.
approve "docs/iterations/ITER-02.md"
t "an approved design passes without a re-render" bash "$GATES_DIR/design.sh"

unapprove "docs/user_stories/US-001-test.md"
unapprove "tests/features/US-002-test.feature"
t_rc "discover exits 3 when only approvals are missing" 3 bash "$GATES_DIR/discover.sh"
t_msg "discover lists every waiting artifact: the story" "US-001-test.md is not approved" \
  bash "$GATES_DIR/discover.sh"
t_msg "discover lists every waiting artifact: the feature" "US-002-test.feature is not approved" \
  bash "$GATES_DIR/discover.sh"
printf -- '---\nid: US-009\nreferences: [x]\n---\n# no role, no want, no criteria\n' \
  > "$FIXTURE/docs/user_stories/US-009-bad.md"
t_rc "discover exits 1 while a structural check also fails" 1 bash "$GATES_DIR/discover.sh"
rm -f "$FIXTURE/docs/user_stories/US-009-bad.md"
approve "docs/user_stories/US-001-test.md"
approve "tests/features/US-002-test.feature"
t "discover passes again once both are approved" bash "$GATES_DIR/discover.sh"

unapprove "docs/adrs/0001-test.md"
t_rc "architect exits 3 when only the ADR approval is missing" 3 bash "$GATES_DIR/architect.sh"
sed -i '/^## Cross-Cutting Concerns$/d' "$FIXTURE/docs/architecture.md"
t_rc "architect exits 1, not 3, while architecture.md is incomplete" 1 bash "$GATES_DIR/architect.sh"
echo '## Cross-Cutting Concerns' >> "$FIXTURE/docs/architecture.md"
approve "docs/adrs/0001-test.md"

unapprove "docs/plan.md"
t_rc "plan exits 3 when only the plan approval is missing" 3 bash "$GATES_DIR/plan.sh"
approve "docs/plan.md"

# --- modes: who may approve ---------------------------------------------------
#
# build (default) approves nothing. `approved_by: autopilot` is a draft unless
# auto mode is on, unexpired, and in mode full.

approval_fixture autopilot
t_rc "an autopilot marker is a draft while autopilot is off" 3 approved "$FIXTURE/appr.md"
autopilot_on
t_rc "an autopilot marker is a draft in mode build" 3 approved "$FIXTURE/appr.md"
t_msg "the refusal says what would make it count" "mode 'full'" approved "$FIXTURE/appr.md"
autopilot_on --mode full
t "an autopilot marker counts in mode full" approved "$FIXTURE/appr.md"
rewind '.autopilot.expires_at = "2020-01-01T00:00:00Z"'
t_rc "an autopilot marker stops counting when full expires" 3 approved "$FIXTURE/appr.md"
autopilot_on --mode full
rewind 'del(.autopilot.mode)'
t_rc "without a mode field the marker is a draft: a pre-v8 status file is build" 3 \
  approved "$FIXTURE/appr.md"
rm -f "$FIXTURE/appr.md"

# --- build: real walks through advance.sh, no --yes ---------------------------

autopilot_on --max-iterations 1
sed -i 's/^approved_by:.*/approved_by: autopilot/' "$FIXTURE/docs/iterations/ITER-02.md"
render_design ITER-02
t_msg "build refuses a design the agent approved itself" "mode 'full'" auto_advance design
unapprove "docs/iterations/ITER-02.md"
render_design ITER-02
t_msg "build never auto-advances an unapproved design" "is not approved" auto_advance design
t "a refused design leaves the state alone" \
  test "$(status '.current_phase')" = "design" \
    -a "$(status '.iterations.ITER-02.design.gate_passed // false')" = "false"
t_rc "next.sh: an unapproved design is the human's move" 3 next
t_msg "next.sh names the design that is waiting" "ITER-02.md is not approved" next
approve "docs/iterations/ITER-02.md"
t_out "next.sh says advance once the user approved" "action: *advance" next
t "…and advance.sh agrees: build advances a design the user approved" auto_advance design
t "build advances implement" auto_advance implement

# --- decisions ----------------------------------------------------------------
#
# A question the agent may not answer alone. Open = no valid approval marker.

mkdir -p "$FIXTURE/docs/decisions"
printf -- '---\nid: DEC-001\napproved_by:\n---\n# DEC-001 keep or drop\n' \
  > "$FIXTURE/docs/decisions/DEC-001-test.md"
t_msg "an open decision pauses auto-advance" "open decision" auto_advance verify
t_rc "next.sh: an open decision is the human's move" 3 next
t_msg "next.sh names the open decision" "DEC-001-test.md" next
sed -i 's/^approved_by:.*/approved_by: autopilot/' "$FIXTURE/docs/decisions/DEC-001-test.md"
t_msg "an answer from autopilot does not count in build" "open decision" auto_advance verify
approve "docs/decisions/DEC-001-test.md"
t "a decision the user answered releases the loop" auto_advance verify
t "the walk reached release" test "$(status '.current_phase')" = "release"

printf -- '---\nid: DEC-002\napproved_by:\n---\n# DEC-002 ship as is\n' \
  > "$FIXTURE/docs/decisions/DEC-002-test.md"
t_rc "release exits 3 while a decision is open" 3 bash "$GATES_DIR/release.sh"
approve "docs/decisions/DEC-002-test.md"
t "release passes once the decision is answered" bash "$GATES_DIR/release.sh"

autopilot_on --mode full
t_msg "release is never carried, not even in mode full" "release always waits for a human" \
  auto_advance release

# One write: advance.sh used to change status.yaml in about eight separate yq
# calls, with current_phase last. Count them through a wrapper.
YQ_WRAP="$(mktemp -d)"
cat > "$YQ_WRAP/yq" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-i" ] && echo x >> "$YQ_WRAP/writes"; done
exec "$(command -v yq)" "\$@"
EOF
chmod +x "$YQ_WRAP/yq"
t "release advances once the human says so" \
  env PATH="$YQ_WRAP:$PATH" bash "$GATES_DIR/advance.sh" release --yes
t "advance.sh writes status.yaml exactly once" \
  test "$(wc -l < "$YQ_WRAP/writes" | tr -d ' ')" = "1"
rm -rf "$YQ_WRAP"
t "the audit records --yes as --yes, not as the user" \
  grep -q -- 'transition via\*\*: --yes' "$FIXTURE"/audit/release-*.md
t_rc "next.sh: done once release has passed" 4 next

# --- once-phases: build never, full does --------------------------------------

rewind '.current_phase = "plan" | .current_iteration = null
        | .phases.plan.gate_passed = false | .phases.release.gate_passed = false'
autopilot_on
t_msg "build never auto-advances a once-phase" "does not carry 'plan'" auto_advance plan
t_rc "next.sh: a green once-phase in build is the human's transition" 3 next
t_msg "next.sh prints the command that is the human's to run" "advance.sh plan" next
autopilot_on --mode full
t "full auto-advances a once-phase" auto_advance plan
t "…and that opened the first iteration" test "$(status '.current_iteration')" = "ITER-01"

# --- next.sh: what now? -------------------------------------------------------

autopilot_on
status_sum() { cksum < "$FIXTURE/status.yaml"; }
audits() { find "$FIXTURE/audit" -type f | wc -l | tr -d ' '; }
sum_before=$(status_sum); audits_before=$(audits)
next >/dev/null 2>&1 || true
t "next.sh is pure" test "$sum_before" = "$(status_sum)" -a "$audits_before" = "$(audits)"

t "walk ITER-01 to verify" bash -c "
  bash '$GATES_DIR/advance.sh' design < /dev/null && bash '$GATES_DIR/advance.sh' implement < /dev/null"
sed -i 's/- \[x\] US-001 verified/- [ ] US-001 pending/' "$FIXTURE/docs/iterations/ITER-01.md"
t_out "next.sh says work while the gate is red and carried" "action: *work" next
t_fails "…and advance.sh agrees: a red gate does not advance" auto_advance verify

# Stall: a finer expiry. The clock runs from the later of the phase's
# started_at and autopilot.enabled_at — fixed timestamps, no sleeping.
autopilot_on --phase-timeout 60
rewind '.autopilot.enabled_at = "2020-01-01T00:00:00Z"
        | .iterations."ITER-01".verify.started_at = "2020-01-01T00:00:00Z"'
t_rc "next.sh: a phase red past its timeout is the human's move" 3 next
t_msg "next.sh says it stalled" "stalled" next
autopilot_on --phase-timeout 60
t_rc "re-enabling autopilot restarts the stall clock" 0 next
rewind '.autopilot.enabled_at = "2020-01-01T00:00:00Z"'
sed -i 's/- \[ \] US-001 pending/- [x] US-001 verified/' "$FIXTURE/docs/iterations/ITER-01.md"
t_out "a gate that turns green still advances after the timeout" "action: *advance" next

autopilot off >/dev/null
t_rc "next.sh: a green gate without autopilot is the human's transition" 3 next
t_fails "…and advance.sh agrees: it stops for the human" auto_advance verify
sed -i 's/- \[x\] US-001 verified/- [ ] US-001 pending/' "$FIXTURE/docs/iterations/ITER-01.md"
t_rc "next.sh: red and not carried is not work for an unattended loop" 3 next
t_msg "…it still says what the work is" "action: *work" next
sed -i 's/- \[ \] US-001 pending/- [x] US-001 verified/' "$FIXTURE/docs/iterations/ITER-01.md"

# Mode full: where build waits for the user, full lets the agent approve.
rewind '.current_phase = "design" | .current_iteration = "ITER-02" | .iterations."ITER-02" = {}'
unapprove "docs/iterations/ITER-02.md"
render_design ITER-02
autopilot_on --mode full
t_out "next.sh: in mode full the approval is the agent's to give" "action: *approve" next
sed -i '0,/^---$/s/^---$/---\napproved_by: autopilot/' "$FIXTURE/docs/iterations/ITER-02.md"
t "full advances a design the agent approved itself" auto_advance design
autopilot off >/dev/null

# -----------------------------------------------------------------------------

echo
if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures test(s) failed"
  exit 1
fi
echo "RESULT: all tests passed"

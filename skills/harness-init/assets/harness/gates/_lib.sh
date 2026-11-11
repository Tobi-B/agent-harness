#!/usr/bin/env bash
# Shared helpers for harness gates.
#
# Contract: gate scripts (discover.sh, architect.sh, ...) and next.sh are PURE
# CHECKS. They read files and exit — they never mutate status.yaml or write
# audits. Gate exit codes:
#   0  pass
#   1  work needed — a structural check failed
#   2  environment broken — missing tool, wrong yq, bash < 4
#   3  only the human's word is missing — every structural check passed and an
#      approval marker (or an open decision) is all that stands in the way
# State changes happen only through:
#   - gates/advance.sh   (runs the gate, writes the audit, moves the phase)
#   - gates/autopilot.sh (turns auto mode on or off, on the user's instruction)
# Approvals are plain `approved_by:` markers inside the artifacts themselves,
# written by the agent only after the user has approved in conversation.
set -euo pipefail

# Gates use bash 4 features (mapfile, [[ =~ ]]). macOS ships bash 3.2 as
# /bin/bash; fail with the fix instead of a cryptic "mapfile: not found".
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  echo "FAIL: gates need bash >= 4 (found ${BASH_VERSION:-unknown}) — macOS: brew install bash" >&2
  exit 2
fi

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$HARNESS_ROOT/status.yaml"
WORKFLOW_FILE="$HARNESS_ROOT/workflow.yaml"
AUDIT_DIR="$HARNESS_ROOT/audit"
# shellcheck disable=SC2034  # used by sourcing gate scripts
DOCS_DIR="$HARNESS_ROOT/docs"
# The project the harness governs lives one level ABOVE harness/: that is
# where src/, pyproject.toml, package.json, CMakeLists.txt etc. are. Override
# for unusual layouts (and for the self-tests' fixture).
PROJECT_ROOT="${HARNESS_PROJECT_ROOT:-$(cd "$HARNESS_ROOT/.." && pwd)}"
PROJECT_FILE="$HARNESS_ROOT/project.yaml"
GATE_NAME="${GATE_NAME:-$(basename "${BASH_SOURCE[1]:-unknown}" .sh)}"

# A terminal opened before yq/jq were installed keeps the PATH it inherited at
# start, so the tools exist but are invisible. Probe the usual install
# locations before concluding they are missing.
_add_to_path() {
  local dir="$1"
  # %LOCALAPPDATA% is a native Windows path; without conversion it lands in
  # PATH drive-less ("\Users\...") and only resolves on the current drive.
  case "$dir" in
    *\\*) command -v cygpath >/dev/null 2>&1 && dir="$(cygpath -u "$dir")" ;;
  esac
  [ -d "$dir" ] || return 0
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$PATH:$dir" ;;
  esac
}
_add_to_path "${LOCALAPPDATA:-$HOME/AppData/Local}/Microsoft/WinGet/Links"
_add_to_path "/c/ProgramData/chocolatey/bin"
_add_to_path "$HOME/scoop/shims"
_add_to_path "/opt/homebrew/bin"
_add_to_path "/usr/local/bin"
_add_to_path "$HOME/.local/bin"
export PATH

install_hint() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo "winget install MikeFarah.yq jqlang.jq" ;;
    Darwin)               echo "brew install yq jq" ;;
    *)                    echo "see https://github.com/mikefarah/yq#install" ;;
  esac
}

require() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 && return 0
  {
    echo "FAIL: required tool '$tool' not found."
    echo "  install:  $(install_hint)"
    echo "  already installed? a terminal opened before the install keeps its old"
    echo "  PATH — open a new one, or add the install directory to PATH by hand."
  } >&2
  exit 2
}

require yq
require jq

# python-yq (kislyuk) has incompatible syntax; gates need mikefarah yq v4.
if ! yq --version 2>/dev/null | grep -q "mikefarah"; then
  echo "FAIL: 'yq' in PATH is not mikefarah yq v4 (https://github.com/mikefarah/yq)" >&2
  exit 2
fi

pass() {
  echo "PASS: $GATE_NAME"
}

fail() {
  echo "FAIL: $GATE_NAME: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $GATE_NAME: $*" >&2
}

# Exit 3: nothing is left to build or fix here — the human has to speak.
# next.sh relies on this to tell "work needed" from "waiting" without reading
# messages, so call it only after every structural check has passed.
wait_for_human() {
  echo "WAIT: $GATE_NAME: $*" >&2
  exit 3
}

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

now_epoch() {
  date -u +%s
}

# GNU and BSD date disagree on how to format an epoch; try both.
epoch_to_iso() {
  local epoch="$1"
  date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
}

iso_to_epoch() {
  local iso="$1"
  date -u -d "$iso" +%s 2>/dev/null \
    || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null
}

iso_in_seconds() {
  epoch_to_iso "$(( $(now_epoch) + $1 ))"
}

# "45m" / "8h" / "2d" / bare seconds -> seconds. Non-zero exit on garbage.
duration_to_seconds() {
  local spec="$1" num unit
  num="${spec%[smhd]}"
  unit="${spec#"$num"}"
  case "$num" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$unit" in
    ''|s) echo "$num" ;;
    m)    echo $(( num * 60 )) ;;
    h)    echo $(( num * 3600 )) ;;
    d)    echo $(( num * 86400 )) ;;
    *)    return 1 ;;
  esac
}

# Path relative to HARNESS_ROOT — the canonical form used in status.yaml.
# Pure bash: GNU `realpath --relative-to` does not exist on macOS.
rel_to_root() {
  case "$1" in
    "$HARNESS_ROOT"/*) echo "${1#"$HARNESS_ROOT"/}" ;;
    *) echo "$1" ;;
  esac
}

has_frontmatter_field() {
  local file="$1"
  local field="$2"
  # index()==1 instead of a regex: avoids injection via field, and avoids the
  # awk gotcha where `exit 0` in a rule still runs END (whose exit overrides).
  awk -v field="$field" '
    BEGIN { in_fm=0; found=0 }
    { sub(/\r$/, "") }
    /^---$/ { if (in_fm) exit; in_fm=1; next }
    in_fm && index($0, field ":") == 1 { found=1; exit }
    END { exit !found }
  ' "$file"
}

frontmatter_value() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    BEGIN { in_fm=0 }
    { sub(/\r$/, "") }
    /^---$/ { if (in_fm) exit; in_fm=1; next }
    in_fm && index($0, field ":") == 1 {
      val = substr($0, length(field) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      print val
      exit
    }
  ' "$file"
}

hardcap() {
  yq ".hardcaps.$1" "$WORKFLOW_FILE"
}

phase_next() {
  yq ".phases[] | select(.id == \"$1\") | .next" "$WORKFLOW_FILE"
}

phase_scope() {
  yq ".phases[] | select(.id == \"$1\") | .scope // \"once\"" "$WORKFLOW_FILE"
}

require_gate_passed() {
  local prev="$1"
  local passed
  passed=$(yq ".phases.${prev}.gate_passed" "$STATUS_FILE")
  [ "$passed" = "true" ] \
    || fail "prerequisite phase '$prev' has not passed its gate (user runs: bash gates/advance.sh $prev)"
}

# --- iterations --------------------------------------------------------------
#
# The iteration list lives in the YAML frontmatter of docs/plan.md, which the
# user signs off. status.yaml only tracks which iteration is current and which
# of its phase gates have passed — the plan stays the single source of truth
# for what the iterations ARE.

PLAN_FILE="$DOCS_DIR/plan.md"

frontmatter_yaml() {
  awk '{ sub(/\r$/, "") } /^---[[:space:]]*$/ { n++; next } n == 1' "$1"
}

plan_iteration_ids() {
  [ -f "$PLAN_FILE" ] || return 0
  frontmatter_yaml "$PLAN_FILE" | yq '.iterations[].id'
}

plan_iteration_field() {
  local id="$1" field="$2"
  frontmatter_yaml "$PLAN_FILE" \
    | yq ".iterations[] | select(.id == \"$id\") | .${field}"
}

next_iteration_id() {
  local current="$1" found=0 id
  while read -r id; do
    [ -n "$id" ] || continue
    if [ "$found" = "1" ]; then echo "$id"; return 0; fi
    [ "$id" = "$current" ] && found=1
  done < <(plan_iteration_ids)
  return 0
}

# No `| head -1`: under pipefail, head closing the pipe early SIGPIPEs the
# writer (exit 141) — advance.sh plan then died silently after "PASS: plan"
# in roughly 40% of runs. Ask yq for the first element instead.
first_iteration_id() {
  [ -f "$PLAN_FILE" ] || return 0
  local id
  id=$(frontmatter_yaml "$PLAN_FILE" | yq '.iterations[0].id // ""')
  [ "$id" = "null" ] && id=""
  echo "$id"
}

current_iteration() {
  local it
  it=$(yq '.current_iteration // ""' "$STATUS_FILE")
  [ "$it" = "null" ] && it=""
  echo "$it"
}

require_current_iteration() {
  local it
  it=$(current_iteration)
  [ -n "$it" ] \
    || fail "no current_iteration in status.yaml — advance past 'plan' first (user runs: bash gates/advance.sh plan)"
  echo "$it"
}

iteration_gate_passed() {
  local iter="$1" phase="$2"
  yq ".iterations.\"${iter}\".${phase}.gate_passed // false" "$STATUS_FILE"
}

require_iteration_gate_passed() {
  local iter="$1" phase="$2"
  [ "$(iteration_gate_passed "$iter" "$phase")" = "true" ] \
    || fail "iteration $iter has not passed its '$phase' gate (user runs: bash gates/advance.sh $phase)"
}

# --- approval ----------------------------------------------------------------
#
# An artifact counts as approved when it carries an explicit approval marker:
# `approved_by: <who>` in its YAML frontmatter (markdown artifacts) or a
# `# approved_by: <who>` comment line (e.g. Gherkin .feature files). The agent
# writes the marker, but only after the user has actually approved in
# conversation — a simple "approved by user" is the whole record, by deliberate
# choice (see docs/adrs/meta-0004-trusted-approval-markers.md). There is no
# hash: if an approved artifact changes materially afterwards, ask the user
# again and refresh the marker.

# Only two values count: `user` and `autopilot` (optionally followed by a note,
# e.g. `user (2026-09-21)`). Anything else — empty, `""`, `TBD`, `pending`, or
# a template's inline `# comment` — is a DRAFT, not an approval. An allowlist
# rather than "non-empty": agents like placeholders, and a placeholder that
# silently counts as approval defeats the harness at its core.
#
# `autopilot` counts only while auto mode is on, unexpired and in mode `full`
# (meta-0008). In the default mode `build` autopilot carries transitions and
# never approves, so there only `user` is an approval — this function is where
# that boundary is enforced. Validity is judged when a gate runs: markers
# written under `full` stay in the files as a record, and a gate that already
# passed is not asked again.
approved_by_of() {
  local file="$1" val
  val=$(frontmatter_value "$file" "approved_by")
  if [ -z "$val" ] && [[ "$file" == *.feature ]]; then
    val=$(sed -n '/^#[[:space:]]*approved_by:/{s/^#[[:space:]]*approved_by:[[:space:]]*//;s/\r$//;p;q;}' "$file")
  fi
  val="${val%%#*}"                        # drop inline YAML comment
  val="${val//\"/}"; val="${val//\'/}"     # drop quotes
  val="${val#"${val%%[![:space:]]*}"}"    # trim
  val="${val%"${val##*[![:space:]]}"}"
  echo "$val"
}

approval_is_valid() {
  case "$1" in
    user|"user "*) return 0 ;;
    autopilot|"autopilot "*) autopilot_may_approve ;;
    *) return 1 ;;
  esac
}

# Why a file does not count as approved, in one line. Silent when it does.
approval_problem() {
  local file="$1" rel who
  rel=$(rel_to_root "$file")
  who=$(approved_by_of "$file")
  if [ -z "$who" ]; then
    echo "$rel is not approved — after the user approves, add 'approved_by: user' to its frontmatter (or a '# approved_by: user' comment in a .feature file)"
    return 0
  fi
  approval_is_valid "$who" && return 0
  case "$who" in
    autopilot|"autopilot "*)
      echo "$rel is not approved — 'approved_by: autopilot' counts only while auto mode is on in mode 'full'; the user has to approve it" ;;
    *)
      echo "$rel is not approved — it has 'approved_by: $who', and only 'user' or 'autopilot' count; anything else is a draft" ;;
  esac
}

# Call LAST in a gate, with every artifact that needs approval: lists all of
# them that are still waiting, then exits 3. Listing them all means the user
# is asked once, not once per file.
require_approved() {
  local file problem waiting=0
  for file in "$@"; do
    problem=$(approval_problem "$file")
    if [ -n "$problem" ]; then
      echo "WAIT: $GATE_NAME: $problem" >&2
      waiting=1
    fi
  done
  [ "$waiting" -eq 0 ] || exit 3
}

# --- decisions -----------------------------------------------------------------
#
# A question the agent may not answer alone becomes docs/decisions/DEC-NNN-*.md
# carrying the same approval marker as every other artifact. Without a valid
# marker it is OPEN: autopilot carries nothing and release does not pass. That
# is the whole format — no status field, no second vocabulary (meta-0008).

DECISIONS_DIR="$DOCS_DIR/decisions"

open_decisions() {
  local f
  [ -d "$DECISIONS_DIR" ] || return 0
  for f in "$DECISIONS_DIR"/DEC-*.md; do
    [ -e "$f" ] || continue
    approval_is_valid "$(approved_by_of "$f")" || rel_to_root "$f"
  done
}

# --- autopilot ---------------------------------------------------------------
#
# Auto mode has two named modes, fixed here in code (meta-0008):
#
#   build  (default) the human decides, the agent builds. Autopilot carries the
#          TRANSITIONS of design/implement/verify and approves nothing: stories,
#          ADRs, the plan and every iteration design still need the user.
#   full   the agent runs every phase except release alone and may mark its
#          own artifacts `approved_by: autopilot`. Has to be asked for by name.
#
# Release always waits for a human. Both modes stay bounded: wall-clock expiry
# and an iteration budget are the emergency brake. Everything here is a pure
# read; autopilot.sh does the writing, advance.sh spends the budget.

AUTOPILOT_PHASES_BUILD="design implement verify"
AUTOPILOT_PHASES_FULL="discover architect model plan design implement verify"

autopilot_field() {
  yq ".autopilot.$1" "$STATUS_FILE" 2>/dev/null
}

# A status file written before v8 has no mode: that means build, the mode that
# hands over less.
autopilot_mode() {
  if [ "$(autopilot_field mode)" = "full" ]; then echo full; else echo build; fi
}

autopilot_phase_in_scope() {
  local phases="$AUTOPILOT_PHASES_BUILD"
  [ "$(autopilot_mode)" = "full" ] && phases="$AUTOPILOT_PHASES_FULL"
  case " $phases " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# May `approved_by: autopilot` count right now? Only in full, and only while
# auto mode is actually on.
autopilot_may_approve() {
  [ "$(autopilot_mode)" = "full" ] && autopilot_on_and_unexpired >/dev/null 2>&1
}

# On and not expired — ignores the budget. Prints the reason when not.
autopilot_on_and_unexpired() {
  local enabled expires_at now exp
  enabled=$(autopilot_field enabled)
  if [ "$enabled" != "true" ]; then
    echo "autopilot is off"
    return 1
  fi

  expires_at=$(autopilot_field expires_at)
  if [ -n "$expires_at" ] && [ "$expires_at" != "null" ]; then
    now=$(now_epoch)
    exp=$(iso_to_epoch "$expires_at" || echo "")
    if [ -z "$exp" ]; then
      echo "autopilot has an unreadable expires_at ($expires_at)"
      return 1
    fi
    if [ "$now" -ge "$exp" ]; then
      echo "autopilot expired at $expires_at"
      return 1
    fi
  fi
  return 0
}

# Prints the reason it is NOT usable, and returns non-zero. Silent + zero when
# it is. Callers use the reason verbatim in their messages.
autopilot_enabled_and_valid() {
  local used maxi
  autopilot_on_and_unexpired || return 1

  used=$(autopilot_field iterations_used)
  maxi=$(autopilot_field max_iterations)
  case "$used" in ''|null|*[!0-9]*) used=0 ;; esac
  case "$maxi" in ''|null|*[!0-9]*) maxi=0 ;; esac
  if [ "$used" -ge "$maxi" ]; then
    echo "autopilot used its budget of $maxi iteration(s)"
    return 1
  fi

  return 0
}

# Does autopilot carry THIS phase right now? Prints why not and returns
# non-zero; silent and zero when it does. This is the one predicate both
# advance.sh (may I skip the prompt?) and next.sh (what now?) ask, so the two
# cannot disagree.
#
# The budget counts ITERATIONS: once an iteration is claimed, autopilot
# finishes it (design → implement → verify) even when that claim used the last
# unit of budget. Otherwise --max-iterations N would strand iteration N after
# its design phase.
autopilot_block_reason() {
  local phase="$1" reason open iter
  if ! reason=$(autopilot_on_and_unexpired); then
    echo "$reason"
    return 1
  fi
  if ! autopilot_phase_in_scope "$phase"; then
    if [ "$phase" = "release" ]; then
      echo "release always waits for a human — autopilot does not carry 'release'"
    else
      echo "autopilot mode '$(autopilot_mode)' does not carry '$phase'"
    fi
    return 1
  fi
  open=$(open_decisions)
  if [ -n "$open" ]; then
    echo "open decision waiting for the user: ${open//$'\n'/, }"
    return 1
  fi
  if [ "$(phase_scope "$phase")" = "iteration" ]; then
    iter=$(current_iteration)
    if [ -n "$iter" ] && autopilot_iteration_claimed "$iter"; then
      return 0
    fi
  fi
  if ! reason=$(autopilot_enabled_and_valid); then
    echo "$reason"
    return 1
  fi
  return 0
}

autopilot_active_for() {
  autopilot_block_reason "$1" >/dev/null 2>&1
}

# Has the current phase been red for longer than the configured timeout?
# Measured from the later of the phase's started_at (advance.sh records it) and
# autopilot.enabled_at, so re-enabling auto mode restarts the clock. A finer
# expiry, not a measure of effort; off unless a timeout was set. Only next.sh
# asks — a gate that turns green still advances.
phase_stalled() {
  local phase="$1" timeout iter started enabled s e ref=0
  timeout=$(autopilot_field phase_timeout_s)
  case "$timeout" in ''|null|*[!0-9]*) timeout=0 ;; esac
  [ "$timeout" -gt 0 ] || return 1

  if [ "$(phase_scope "$phase")" = "iteration" ]; then
    iter=$(current_iteration)
    started=$(yq ".iterations.\"${iter}\".${phase}.started_at // \"\"" "$STATUS_FILE")
  else
    started=$(yq ".phases.${phase}.started_at // \"\"" "$STATUS_FILE")
  fi
  enabled=$(autopilot_field enabled_at)
  for s in "$started" "$enabled"; do
    [ -n "$s" ] && [ "$s" != "null" ] || continue
    e=$(iso_to_epoch "$s" || echo 0)
    [ -n "$e" ] && [ "$e" -gt "$ref" ] && ref="$e"
  done
  [ "$ref" -gt 0 ] || return 1
  [ $(( $(now_epoch) - ref )) -gt "$timeout" ]
}

# Has this iteration already been charged against the budget?
autopilot_iteration_claimed() {
  local iter="$1"
  [ "$(yq ".autopilot.iterations_claimed // [] | any_c(. == \"$iter\")" "$STATUS_FILE" 2>/dev/null)" = "true" ]
}

print_autopilot_status() {
  local reason mode phases budget_note=""
  mode=$(autopilot_mode)
  phases="$AUTOPILOT_PHASES_BUILD"
  [ "$mode" = "full" ] && phases="$AUTOPILOT_PHASES_FULL"
  if reason=$(autopilot_on_and_unexpired); then
    echo "autopilot: ON (mode: $mode)"
    # A spent budget does not switch autopilot off: the iteration that spent
    # it still finishes, only a new one does not start.
    autopilot_enabled_and_valid >/dev/null 2>&1 \
      || budget_note="  — spent: a claimed iteration still finishes, no new one starts"
  else
    echo "autopilot: OFF ($reason)"
  fi
  echo "  mode:               $mode"
  echo "  carries:            ${phases// /, }"
  if [ "$mode" = "full" ]; then
    echo "  approves:           its own artifacts, as 'approved_by: autopilot'"
  else
    echo "  approves:           nothing — approvals stay with the user"
  fi
  echo "  expires_at:         $(autopilot_field expires_at)"
  echo "  iterations_used:    $(autopilot_field iterations_used) / $(autopilot_field max_iterations)${budget_note}"
  echo "  phase_timeout_s:    $(autopilot_field phase_timeout_s)"
  echo "  iterations_claimed: $(yq -o=json '.autopilot.iterations_claimed // []' "$STATUS_FILE" | jq -r 'join(", ") | if . == "" then "-" else . end')"
  echo "  enabled_by:         $(autopilot_field enabled_by)"
}

# --- project config (harness/project.yaml) --------------------------------
#
# Project-owned, NOT part of the workflow contract: which commands the
# implement gate runs. Editing it is normal project work (no meta ADR).

project_cfg() {
  [ -f "$PROJECT_FILE" ] || { echo ""; return 0; }
  local v
  # No `// ""` here: yq's alternative operator also swallows `false`.
  v=$(yq "$1" "$PROJECT_FILE")
  [ "$v" = "null" ] && v=""
  echo "$v"
}

# --- mutations below: ONLY for advance.sh / autopilot.sh ---
#
# status.yaml is changed by ONE yq call per operation. advance.sh used to make
# about eight, setting current_phase last: an interruption in between left a
# once-phase passed but still current, and advance.sh then refused it for good.
# Callers build the expression from fragments and apply it once.

status_apply() {
  yq -i "$1" "$STATUS_FILE"
}

# The yq fragment that charges an iteration to the autopilot budget. Empty when
# the iteration is already claimed — a claim is paid for once.
autopilot_claim_expr() {
  local iter="$1" used
  if autopilot_iteration_claimed "$iter"; then
    return 0
  fi
  used=$(autopilot_field iterations_used)
  case "$used" in ''|null|*[!0-9]*) used=0 ;; esac
  echo ".autopilot.iterations_claimed = ((.autopilot.iterations_claimed // []) + [\"${iter}\"]) | .autopilot.iterations_used = $(( used + 1 ))"
}

autopilot_claim_iteration() {
  local expr
  expr=$(autopilot_claim_expr "$1")
  [ -n "$expr" ] || return 0
  status_apply "$expr | .last_updated = \"$(now_iso)\""
}

ensure_audit_dir() {
  mkdir -p "$AUDIT_DIR"
}

write_audit() {
  ensure_audit_dir
  local ts file
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  file="$AUDIT_DIR/${GATE_NAME}-${ts}.md"
  cat > "$file"
  echo "audit: $file"
}

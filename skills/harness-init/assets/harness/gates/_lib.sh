#!/usr/bin/env bash
# Shared helpers for harness gates.
#
# Contract: gate scripts (discover.sh, architect.sh, ...) are PURE CHECKS.
# They read files and exit 0/1 — they never mutate status.yaml or write audits.
# State changes happen only through:
#   - gates/advance.sh   (run by the USER: runs the gate, writes audit, advances phase)
#   - gates/autopilot.sh (run by the USER: bounded auto-approve for the iteration cycle)
# Approvals are plain `approved_by:` markers inside the artifacts themselves,
# written by the agent only after the user has approved in conversation.
set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$HARNESS_ROOT/status.yaml"
WORKFLOW_FILE="$HARNESS_ROOT/workflow.yaml"
AUDIT_DIR="$HARNESS_ROOT/audit"
# shellcheck disable=SC2034  # used by sourcing gate scripts
DOCS_DIR="$HARNESS_ROOT/docs"
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
  {
    echo "FAIL: the 'yq' found at $(command -v yq) is not mikefarah yq v4."
    echo "  python-yq (kislyuk) uses incompatible syntax and will not work."
    echo "  install: $(install_hint)"
  } >&2
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
rel_to_root() {
  realpath --relative-to="$HARNESS_ROOT" "$1"
}

has_frontmatter_field() {
  local file="$1"
  local field="$2"
  # index()==1 instead of a regex: avoids injection via field, and avoids the
  # awk gotcha where `exit 0` in a rule still runs END (whose exit overrides).
  awk -v field="$field" '
    BEGIN { in_fm=0; found=0 }
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
  awk '/^---[[:space:]]*$/ { n++; next } n == 1' "$1"
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

first_iteration_id() {
  plan_iteration_ids | head -1
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

approved_by_of() {
  local file="$1" val
  val=$(frontmatter_value "$file" "approved_by")
  if [ -z "$val" ]; then
    val=$(sed -n 's/^#[[:space:]]*approved_by:[[:space:]]*//p' "$file" | head -1)
  fi
  echo "$val"
}

require_approved() {
  local file="$1" rel who
  rel=$(rel_to_root "$file")
  who=$(approved_by_of "$file")
  [ -n "$who" ] && [ "$who" != "null" ] \
    || fail "$rel is not approved — after the user approves, add 'approved_by: user' to its frontmatter (or a '# approved_by: user' comment in a .feature file)"
}

# --- autopilot ---------------------------------------------------------------
#
# Auto mode: WITHOUT it the cycle is human-in-the-loop (the user approves every
# artifact and every transition); WITH it the agent runs the whole machine
# alone — every phase except release, which always waits for a human. It stays
# bounded: wall-clock expiry and an iteration budget act as the emergency
# brake. Everything here is a pure read; autopilot.sh does the writing,
# advance.sh spends the budget.

AUTOPILOT_PHASES="discover architect model plan design implement verify"

autopilot_field() {
  yq ".autopilot.$1" "$STATUS_FILE" 2>/dev/null
}

autopilot_phase_in_scope() {
  case " $AUTOPILOT_PHASES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints the reason it is NOT usable, and returns non-zero. Silent + zero when
# it is. Callers use the reason verbatim in their messages.
autopilot_enabled_and_valid() {
  local enabled expires_at used maxi now exp
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

# Is autopilot usable for THIS phase right now?
autopilot_active_for() {
  local phase="$1"
  autopilot_phase_in_scope "$phase" || return 1
  autopilot_enabled_and_valid >/dev/null 2>&1
}

# Has this iteration already been charged against the budget?
autopilot_iteration_claimed() {
  local iter="$1"
  [ "$(yq ".autopilot.iterations_claimed[]? | select(. == \"$iter\")" "$STATUS_FILE" 2>/dev/null | head -1)" = "$iter" ]
}

print_autopilot_status() {
  local reason
  if reason=$(autopilot_enabled_and_valid); then
    :
  fi
  if autopilot_enabled_and_valid >/dev/null 2>&1; then
    echo "autopilot: ON"
  else
    echo "autopilot: OFF ($reason)"
  fi
  echo "  scope:              ${AUTOPILOT_PHASES// /, } (everything except release)"
  echo "  expires_at:         $(autopilot_field expires_at)"
  echo "  iterations_used:    $(autopilot_field iterations_used) / $(autopilot_field max_iterations)"
  echo "  iterations_claimed: $(yq -o=json '.autopilot.iterations_claimed // []' "$STATUS_FILE" | jq -r 'join(", ") | if . == "" then "-" else . end')"
  echo "  enabled_by:         $(autopilot_field enabled_by)"
}

# --- mutations below: ONLY for advance.sh / autopilot.sh ---

set_status() {
  local phase="$1"
  local key="$2"
  local value="$3"
  case "$value" in
    true|false)
      yq -i ".phases.${phase}.${key} = ${value}" "$STATUS_FILE"
      ;;
    *)
      yq -i ".phases.${phase}.${key} = \"${value}\"" "$STATUS_FILE"
      ;;
  esac
  yq -i ".last_updated = \"$(now_iso)\"" "$STATUS_FILE"
}

set_current_phase() {
  local phase="$1"
  yq -i ".current_phase = \"${phase}\"" "$STATUS_FILE"
}

set_current_iteration() {
  local iter="$1"
  if [ -z "$iter" ]; then
    yq -i ".current_iteration = null" "$STATUS_FILE"
  else
    yq -i ".current_iteration = \"${iter}\"" "$STATUS_FILE"
    # Ensure the per-iteration record exists (mikefarah yq has no //= operator).
    yq -i ".iterations.\"${iter}\" = (.iterations.\"${iter}\" // {})" "$STATUS_FILE"
  fi
}

set_iteration_status() {
  local iter="$1" phase="$2" key="$3" value="$4"
  case "$value" in
    true|false)
      yq -i ".iterations.\"${iter}\".${phase}.${key} = ${value}" "$STATUS_FILE"
      ;;
    *)
      yq -i ".iterations.\"${iter}\".${phase}.${key} = \"${value}\"" "$STATUS_FILE"
      ;;
  esac
  yq -i ".last_updated = \"$(now_iso)\"" "$STATUS_FILE"
}

autopilot_claim_iteration() {
  local iter="$1" used
  autopilot_iteration_claimed "$iter" && return 0
  used=$(autopilot_field iterations_used)
  case "$used" in ''|null|*[!0-9]*) used=0 ;; esac
  export AP_ITER="$iter"
  yq -i '.autopilot.iterations_claimed += [strenv(AP_ITER)]' "$STATUS_FILE"
  yq -i ".autopilot.iterations_used = $(( used + 1 ))" "$STATUS_FILE"
  yq -i ".last_updated = \"$(now_iso)\"" "$STATUS_FILE"
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

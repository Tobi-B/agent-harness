#!/usr/bin/env bash
# Shared helpers for harness gates.
#
# Contract: gate scripts (discover.sh, architect.sh, ...) are PURE CHECKS.
# They read files and exit 0/1 — they never mutate status.yaml or write audits.
# State changes happen only through:
#   - gates/signoff.sh  (run by the USER: records artifact sha256 in status.yaml)
#   - gates/advance.sh  (run by the USER: runs the gate, writes audit, advances phase)
set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATUS_FILE="$HARNESS_ROOT/status.yaml"
WORKFLOW_FILE="$HARNESS_ROOT/workflow.yaml"
AUDIT_DIR="$HARNESS_ROOT/audit"
# shellcheck disable=SC2034  # used by sourcing gate scripts
DOCS_DIR="$HARNESS_ROOT/docs"
GATE_NAME="${GATE_NAME:-$(basename "${BASH_SOURCE[1]:-unknown}" .sh)}"

require() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "FAIL: required tool '$tool' not in PATH" >&2
    exit 2
  fi
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

now_iso() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
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

recorded_signoff_hash() {
  local rel="$1"
  yq ".signed_off_artifacts[] | select(.path == \"$rel\") | .sha256" "$STATUS_FILE" 2>/dev/null | head -1
}

# An artifact counts as signed off only if status.yaml holds a sign-off entry
# whose sha256 matches the file's CURRENT content. Editing after sign-off
# invalidates the sign-off — by design.
require_signed_off() {
  local file="$1"
  local rel recorded current
  rel=$(rel_to_root "$file")
  recorded=$(recorded_signoff_hash "$rel")
  [ -n "$recorded" ] && [ "$recorded" != "null" ] \
    || fail "$rel has no sign-off (user runs: bash gates/signoff.sh $rel)"
  current=$(sha256_of "$file")
  [ "$recorded" = "$current" ] \
    || fail "$rel was modified after sign-off (hash mismatch) — re-request approval, then user re-runs: bash gates/signoff.sh $rel"
}

# --- mutations below: ONLY for signoff.sh / advance.sh, never for gates ---

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

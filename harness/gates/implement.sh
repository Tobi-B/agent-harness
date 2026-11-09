#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh implement.
#
# Iteration-scoped: implements the design approved for the current iteration.
#
# Stack-neutral: the commands come from harness/project.yaml (test, lint,
# acceptance) and run from the PROJECT root — the directory that contains
# harness/, not harness/ itself. A Python project with pyproject.toml and no
# configured commands falls back to pytest / ruff / behave.
#
# No silent passes: a missing source directory, an unconfigured command, or an
# absent tool FAILS the gate. HARNESS_ALLOW_MISSING_TOOLS=1 downgrades those to
# warnings (explicit opt-out, e.g. docs-only repos). A command that runs and
# fails is never downgraded.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="implement"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

iter=$(require_current_iteration)
require_iteration_gate_passed "$iter" design

FEATURES_DIR="$HARNESS_ROOT/tests/features"

# Every story in this iteration must have its executable acceptance contract.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  [ -f "$FEATURES_DIR/${s}.feature" ] \
    || [ -n "$(find "$FEATURES_DIR" -maxdepth 1 -name "${s}-*.feature" -print -quit 2>/dev/null)" ] \
    || fail "story $s (iteration $iter) has no tests/features/${s}-*.feature"
done

soft_fail() {
  if [ "${HARNESS_ALLOW_MISSING_TOOLS:-0}" = "1" ]; then
    warn "$* — skipped (HARNESS_ALLOW_MISSING_TOOLS=1)"
    return 0
  fi
  fail "$* (set HARNESS_ALLOW_MISSING_TOOLS=1 to skip explicitly)"
}

# --- which commands? ----------------------------------------------------------
is_python=0
[ -f "$PROJECT_ROOT/pyproject.toml" ] && is_python=1

cmd_for() {
  local kind="$1" cmd
  cmd=$(project_cfg ".commands.$kind")
  if [ -z "$cmd" ] && [ "$is_python" = "1" ]; then
    case "$kind" in
      test)       cmd="pytest -q" ;;
      lint)       cmd="ruff check ." ;;
      acceptance) cmd="behave harness/tests/features --no-capture --no-color" ;;
    esac
  fi
  echo "$cmd"
}

run_cmd() {
  local kind="$1" cmd tool log
  cmd=$(cmd_for "$kind")
  if [ -z "$cmd" ]; then
    soft_fail "no '$kind' command configured in harness/project.yaml (commands.$kind)"
    return 0
  fi
  # First word of the command, skipping leading VAR=value assignments.
  tool="$cmd"
  while [[ "$tool" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; do
    tool="${BASH_REMATCH[1]}"
  done
  tool="${tool%% *}"
  if ! command -v "$tool" >/dev/null 2>&1; then
    soft_fail "'$kind' command needs '$tool', which is not in PATH"
    return 0
  fi
  echo "run [$kind]: $cmd"
  log=$(mktemp)
  if ! (cd "$PROJECT_ROOT" && bash -c "$cmd") >"$log" 2>&1; then
    tail -40 "$log" >&2
    rm -f "$log"
    fail "'$kind' failed: $cmd"
  fi
  tail -3 "$log"
  rm -f "$log"
}

# --- source must exist --------------------------------------------------------
mapfile -t src_dirs < <(project_cfg '.source_dirs[]')
[ "${#src_dirs[@]}" -gt 0 ] || src_dirs=(src)

existing=()
for d in "${src_dirs[@]}"; do
  [ -d "$PROJECT_ROOT/$d" ] && existing+=("$PROJECT_ROOT/$d")
done

if [ "${#existing[@]}" -eq 0 ]; then
  soft_fail "no source found in ${src_dirs[*]} under $PROJECT_ROOT — set source_dirs in harness/project.yaml"
else
  # Comments included: that is where TODO/FIXME markers live.
  if [ "$(project_cfg '.todo_check')" != "false" ]; then
    todo_hits=$(grep -rInE '\b(TODO|FIXME)\b' "${existing[@]}" \
      --exclude-dir=node_modules --exclude-dir=__pycache__ --exclude-dir=.git \
      --exclude-dir=build --exclude-dir=dist --exclude-dir=target \
      --exclude-dir=.venv --exclude-dir=venv 2>/dev/null | head -20 || true)
    [ -z "$todo_hits" ] || fail "TODO/FIXME in delivered code:
$todo_hits"
  fi
fi

run_cmd test
run_cmd lint
run_cmd acceptance

pass

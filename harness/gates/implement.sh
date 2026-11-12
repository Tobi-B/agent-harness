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
# absent tool FAILS the gate. `allow_missing_tools: true` in project.yaml (or
# HARNESS_ALLOW_MISSING_TOOLS=1 at a terminal, not under autopilot) downgrades
# those to warnings. A command that runs and fails is never downgraded.
#
# The command runner is shared with verify and release (_lib.sh).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="implement"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

iter=$(require_current_iteration)
require_iteration_gate_passed "$iter" design

# Every story in this iteration must have its executable acceptance contract.
mapfile -t stories < <(plan_iteration_field "$iter" "stories[]")
for s in "${stories[@]}"; do
  [ -f "$FEATURES_DIR/${s}.feature" ] \
    || [ -n "$(find "$FEATURES_DIR" -maxdepth 1 -name "${s}-*.feature" -print -quit 2>/dev/null)" ] \
    || fail "story $s (iteration $iter) has no tests/features/${s}-*.feature"
done

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

# Acceptance covers the stories due by this iteration — earlier ones too, as a
# regression check, but not the stories of later iterations, whose steps do
# not exist yet (meta-0009).
run_project_commands "$iter"

pass

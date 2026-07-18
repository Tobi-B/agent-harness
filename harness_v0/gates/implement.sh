#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh implement.
#
# Missing test/lint tools FAIL the gate: a quality gate that passes because
# the test runner is absent is a hole. Set HARNESS_ALLOW_MISSING_TOOLS=1 to
# downgrade missing tools to warnings (explicit opt-out, e.g. docs-only repos).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="implement"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

require_gate_passed model

tool_or_fail() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [ "${HARNESS_ALLOW_MISSING_TOOLS:-0}" = "1" ]; then
    warn "tool '$tool' not available, skipping (HARNESS_ALLOW_MISSING_TOOLS=1)"
    return 1
  fi
  fail "tool '$tool' required but not in PATH (set HARNESS_ALLOW_MISSING_TOOLS=1 to skip explicitly)"
}

if [ -d "$HARNESS_ROOT/src" ] || [ -f "$HARNESS_ROOT/pyproject.toml" ]; then
  if tool_or_fail pytest; then
    pytest -q || fail "pytest failed"
  fi

  if tool_or_fail ruff; then
    ruff check "$HARNESS_ROOT/src" "$HARNESS_ROOT/tests" 2>/dev/null \
      || fail "ruff found lint issues"
  fi

  todo_files=$(grep -rEn "^[^#]*\b(TODO|FIXME)\b" "$HARNESS_ROOT/src" 2>/dev/null \
    | grep -v "__pycache__" || true)
  [ -z "$todo_files" ] || fail "TODO/FIXME in src: $todo_files"
else
  echo "INFO: no src/ or pyproject.toml detected; skipping test/lint/TODO gates"
fi

behave_dir="$HARNESS_ROOT/tests/features"
if [ -d "$behave_dir" ] && [ -n "$(find "$behave_dir" -maxdepth 1 -name '*.feature' -print -quit)" ]; then
  if tool_or_fail behave; then
    behave_log=$(mktemp)
    if ! behave "$behave_dir" --no-capture --no-color >"$behave_log" 2>&1; then
      tail -40 "$behave_log" >&2
      rm -f "$behave_log"
      fail "behave reported failures"
    fi
    tail -5 "$behave_log"
    rm -f "$behave_log"
  fi
fi

pass

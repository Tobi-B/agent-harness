#!/usr/bin/env bash
# Regenerate skills/harness-init/assets/ from the harness in this repo.
#
# The skill bundles its own copy of the harness so it can scaffold into any
# project without this repo being present. The assets mirror the repo layout
# exactly, which is what lets harness/init.sh run unchanged from inside the
# skill. This script is the only sanctioned way to update them.
#
#   bash tools/sync-skill.sh          # regenerate assets
#   bash tools/sync-skill.sh --check  # fail if stale (CI)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$REPO_ROOT/skills/harness-init/assets"

# Everything init.sh reads, relative to the repo root.
PAYLOAD=(
  harness
  AGENTS.md
  .shellcheckrc
  .claude/commands/loop.md
  .opencode/command/loop.md
)

check_only=0
[ "${1:-}" = "--check" ] && check_only=1

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

for item in "${PAYLOAD[@]}"; do
  mkdir -p "$stage/$(dirname "$item")"
  cp -r "$REPO_ROOT/$item" "$stage/$(dirname "$item")/"
done

# Project *content* must not travel: a new project starts empty. Only the
# machinery, templates, and the meta ADRs that explain the design ship.
rm -rf "$stage/harness/audit" \
       "$stage/harness/docs/verify-report.md"
rm -f  "$stage/harness/docs/user_stories/US-"* \
       "$stage/harness/docs/uml/"*.mmd \
       "$stage/harness/tests/features/US-"* \
       "$stage/harness/docs/iterations/"*
find "$stage/harness/docs/adrs" -name '000*.md' -delete 2>/dev/null || true
mkdir -p "$stage/harness/audit"

if [ "$check_only" -eq 1 ]; then
  if [ ! -d "$ASSETS" ]; then
    echo "FAIL: $ASSETS missing — run: bash tools/sync-skill.sh" >&2
    exit 1
  fi
  if diff -r -q "$stage" "$ASSETS" >/dev/null 2>&1; then
    echo "PASS: skill assets are in sync with the repo"
    exit 0
  fi
  echo "FAIL: skill assets are stale — run: bash tools/sync-skill.sh" >&2
  diff -r -q "$stage" "$ASSETS" || true
  exit 1
fi

rm -rf "$ASSETS"
mkdir -p "$(dirname "$ASSETS")"
cp -r "$stage" "$ASSETS"
echo "synced harness -> skills/harness-init/assets ($(find "$ASSETS" -type f | wc -l | tr -d ' ') files)"
echo "install to ~/.claude/skills with: bash tools/install-skills.sh"

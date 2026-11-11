#!/usr/bin/env bash
# Install this repo's skills into the personal skill directory, so they are
# available in every project — not just this one.
#
# This repo is the only place the skills are edited. The installed copy is a
# build product: it carries a VERSION file naming the workflow version and the
# commit it came from, and --check tells you whether it still matches.
#
#   bash tools/install-skills.sh           # install to ~/.claude/skills
#   bash tools/install-skills.sh --check   # fail if the installed copy differs
#   CLAUDE_SKILLS_DIR=... bash tools/install-skills.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

check_only=0
case "${1:-}" in
  --check) check_only=1 ;;
  '') ;;
  *) echo "unknown argument: $1 (use --check, or nothing)" >&2; exit 2 ;;
esac

[ -d "$REPO_ROOT/skills/harness-init/assets" ] \
  || { echo "FAIL: skill assets missing — run: bash tools/sync-skill.sh" >&2; exit 1; }

# "workflow v7, commit ca7df63, 2026-11-10" — "-dirty" when the working tree
# has uncommitted changes, so a stamp never claims a commit it does not match.
version_stamp() {
  local wf sha dirty=""
  wf=$(awk '/^version:/ { print $2; exit }' "$REPO_ROOT/harness/workflow.yaml")
  sha=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  [ -z "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ] || dirty="-dirty"
  echo "workflow v${wf}, commit ${sha}${dirty}, $(date -u +%Y-%m-%d)"
}

if [ "$check_only" -eq 1 ]; then
  stale=0
  for skill in "$REPO_ROOT"/skills/*/; do
    name="$(basename "$skill")"
    if [ ! -d "$DEST/$name" ]; then
      echo "MISSING: $name is not installed in $DEST" >&2
      stale=1
    elif diff -r -q -x VERSION "$skill" "$DEST/$name" >/dev/null 2>&1; then
      echo "ok: $name ($(cat "$DEST/$name/VERSION" 2>/dev/null || echo "no VERSION stamp"))"
    else
      echo "STALE: $DEST/$name differs from this repo ($(cat "$DEST/$name/VERSION" 2>/dev/null || echo "no VERSION stamp"))" >&2
      diff -r -q -x VERSION "$skill" "$DEST/$name" 2>&1 | head -10 >&2 || true
      stale=1
    fi
  done
  if [ "$stale" -eq 1 ]; then
    echo "FAIL: installed skills are not this repo's — run: bash tools/install-skills.sh" >&2
    exit 1
  fi
  echo "PASS: installed skills match this repo"
  exit 0
fi

stamp="$(version_stamp)"
mkdir -p "$DEST"
for skill in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$skill")"
  rm -rf "${DEST:?}/$name"
  cp -r "$skill" "$DEST/$name"
  echo "$stamp" > "$DEST/$name/VERSION"
  echo "installed: $name -> $DEST/$name ($stamp)"
done

cat <<EOF

Available now in any project:
  /harness-init    scaffold the harness into a project
  mermaid-render   render .mmd / markdown mermaid blocks to a review page
EOF

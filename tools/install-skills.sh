#!/usr/bin/env bash
# Install this repo's skills into the personal skill directory, so they are
# available in every project — not just this one.
#
#   bash tools/install-skills.sh           # install to ~/.claude/skills
#   CLAUDE_SKILLS_DIR=... bash tools/install-skills.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"

[ -d "$REPO_ROOT/skills/harness-init/assets" ] \
  || { echo "FAIL: skill assets missing — run: bash tools/sync-skill.sh" >&2; exit 1; }

mkdir -p "$DEST"
for skill in "$REPO_ROOT"/skills/*/; do
  name="$(basename "$skill")"
  rm -rf "${DEST:?}/$name"
  cp -r "$skill" "$DEST/$name"
  echo "installed: $name -> $DEST/$name"
done

cat <<EOF

Available now in any project:
  /harness-init    scaffold the harness into a project
  mermaid-render   render .mmd / markdown mermaid blocks to a review page
EOF

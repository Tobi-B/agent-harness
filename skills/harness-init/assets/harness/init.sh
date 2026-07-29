#!/usr/bin/env bash
# Install the harness into a project and start its git-based state loop.
#
# Copies the machinery (gates, workflow, templates, doc skeletons), resets all
# project state to zero, and makes the initial commit. Existing project files
# are never overwritten: if the target already has a harness/, the script stops.
#
# Usage:
#   bash init.sh [TARGET_DIR] [--name NAME] [--no-git] [--force]
#
#   TARGET_DIR   where to install (default: current directory)
#   --name       project name written into the README/state (default: dir name)
#   --no-git     skip git init / initial commit
#   --force      replace an existing harness/ directory in the target
set -euo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SRC_ROOT/.." && pwd)"

target="."
name=""
do_git=1
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name)   name="$2"; shift 2 ;;
    --no-git) do_git=0; shift ;;
    --force)  force=1; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)       echo "unknown option: $1" >&2; exit 2 ;;
    *)        target="$1"; shift ;;
  esac
done

mkdir -p "$target"
target="$(cd "$target" && pwd)"
[ -n "$name" ] || name="$(basename "$target")"

if [ "$target" = "$REPO_ROOT" ]; then
  echo "FAIL: refusing to install the harness into its own source repo" >&2
  exit 2
fi

if [ -d "$target/harness" ]; then
  if [ "$force" -eq 1 ]; then
    echo "WARN: replacing existing $target/harness"
    rm -rf "$target/harness"
  else
    echo "FAIL: $target/harness already exists (use --force to replace)" >&2
    exit 1
  fi
fi

echo "installing harness -> $target"

mkdir -p "$target/harness"

# --- machinery: copied verbatim ----------------------------------------------
cp -r "$SRC_ROOT/gates"     "$target/harness/"
cp -r "$SRC_ROOT/templates" "$target/harness/"
cp    "$SRC_ROOT/workflow.yaml" "$SRC_ROOT/dor_dod.yaml" "$SRC_ROOT/README.md" "$target/harness/"
cp    "$SRC_ROOT/init.sh"   "$target/harness/"

# --- gate self-tests travel with the harness ---------------------------------
mkdir -p "$target/harness/tests/gates" "$target/harness/tests/features"
cp "$SRC_ROOT/tests/gates/test_gates.sh" "$target/harness/tests/gates/"

# --- doc skeletons: templates, not this project's content --------------------
mkdir -p "$target/harness/docs/adrs" "$target/harness/docs/uml" \
         "$target/harness/docs/user_stories" "$target/harness/docs/iterations" \
         "$target/harness/audit"
cp "$SRC_ROOT/docs/prd.md" "$SRC_ROOT/docs/architecture.md" "$SRC_ROOT/docs/plan.md" \
   "$SRC_ROOT/docs/WORKFLOW_CHANGES.md" "$target/harness/docs/"
cp "$SRC_ROOT/docs/adrs/README.md"          "$target/harness/docs/adrs/"
cp "$SRC_ROOT/docs/uml/README.md"           "$target/harness/docs/uml/"
cp "$SRC_ROOT/docs/user_stories/README.md"  "$target/harness/docs/user_stories/"
# The meta ADRs explain WHY the gates are built this way — worth carrying along.
cp "$SRC_ROOT/docs/adrs/"meta-*.md "$target/harness/docs/adrs/" 2>/dev/null || true

for d in docs/adrs docs/uml docs/user_stories docs/iterations audit tests/features; do
  [ -n "$(find "$target/harness/$d" -mindepth 1 -print -quit 2>/dev/null)" ] \
    || touch "$target/harness/$d/.gitkeep"
done

# --- fresh state: no phases passed, no sign-offs, no iterations --------------
cp "$SRC_ROOT/status.yaml" "$target/harness/status.yaml"

# --- agent glue ---------------------------------------------------------------
mkdir -p "$target/.claude/commands" "$target/.opencode/command"
cp "$REPO_ROOT/.claude/commands/harness.md"   "$target/.claude/commands/"
cp "$REPO_ROOT/.opencode/command/harness.md"  "$target/.opencode/command/"
cp "$REPO_ROOT/.shellcheckrc"              "$target/.shellcheckrc"

if [ -f "$target/AGENTS.md" ]; then
  echo "WARN: $target/AGENTS.md exists — wrote AGENTS.harness.md instead; merge it manually"
  cp "$REPO_ROOT/AGENTS.md" "$target/AGENTS.harness.md"
else
  cp "$REPO_ROOT/AGENTS.md" "$target/AGENTS.md"
fi

sed -i "s|^# Agent Instructions (portable)|# Agent Instructions — ${name}|" \
  "$target/AGENTS.md" 2>/dev/null || true

# --- git ----------------------------------------------------------------------
if [ "$do_git" -eq 1 ]; then
  if [ -d "$target/.git" ]; then
    echo "INFO: $target is already a git repo; skipping git init"
  else
    git -C "$target" init -q -b main
    echo "INFO: initialised git repo"
  fi
  cat >> "$target/.gitignore" <<'EOF'

# Claude Code local machine-specific settings
.claude/settings.local.json
EOF
  git -C "$target" add -A
  if git -C "$target" diff --cached --quiet; then
    echo "INFO: nothing to commit"
  else
    git -C "$target" commit -q -m "chore: scaffold lean harness

Phase machine: discover → architect → model → plan → ⟳(design → implement → verify) → release
Gates are pure checks; sign-off and phase transitions are user actions."
    echo "INFO: initial commit created"
  fi
fi

cat <<EOF

harness installed in $target

  next: open the project and run /harness  (or: bash harness/gates/discover.sh)

  state:    harness/status.yaml       (phase: discover, no sign-offs yet)
  contract: harness/workflow.yaml
  fill in:  harness/docs/prd.md       — the discover gate checks it

  sign off an artifact:  bash harness/gates/signoff.sh <path>
  advance a phase:       bash harness/gates/advance.sh <phase>
EOF

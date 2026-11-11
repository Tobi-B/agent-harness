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
cp    "$SRC_ROOT/workflow.yaml" "$SRC_ROOT/dor_dod.yaml" "$SRC_ROOT/README.md" \
      "$SRC_ROOT/project.yaml" "$target/harness/"
cp    "$SRC_ROOT/init.sh"   "$target/harness/"
if [ -d "$SRC_ROOT/glue" ]; then
  cp -r "$SRC_ROOT/glue" "$target/harness/"
fi

# --- gate self-tests travel with the harness ---------------------------------
mkdir -p "$target/harness/tests/gates" "$target/harness/tests/features"
cp "$SRC_ROOT/tests/gates/test_gates.sh" "$target/harness/tests/gates/"

# --- doc skeletons: templates, not this project's content --------------------
mkdir -p "$target/harness/docs/adrs" "$target/harness/docs/uml" \
         "$target/harness/docs/user_stories" "$target/harness/docs/iterations" \
         "$target/harness/docs/decisions" "$target/harness/audit"
cp "$SRC_ROOT/docs/prd.md" "$SRC_ROOT/docs/architecture.md" "$SRC_ROOT/docs/plan.md" \
   "$SRC_ROOT/docs/WORKFLOW_CHANGES.md" "$target/harness/docs/"
cp "$SRC_ROOT/docs/adrs/README.md"          "$target/harness/docs/adrs/"
cp "$SRC_ROOT/docs/uml/README.md"           "$target/harness/docs/uml/"
cp "$SRC_ROOT/docs/user_stories/README.md"  "$target/harness/docs/user_stories/"
# The meta ADRs explain WHY the gates are built this way — worth carrying along.
cp "$SRC_ROOT/docs/adrs/"meta-*.md "$target/harness/docs/adrs/" 2>/dev/null || true

for d in docs/adrs docs/uml docs/user_stories docs/iterations docs/decisions audit tests/features; do
  [ -n "$(find "$target/harness/$d" -mindepth 1 -print -quit 2>/dev/null)" ] \
    || touch "$target/harness/$d/.gitkeep"
done

# --- fresh state: no phases passed, no approvals, no iterations --------------
cp "$SRC_ROOT/status.yaml" "$target/harness/status.yaml"

# --- agent glue ---------------------------------------------------------------
# Canonical copies live VISIBLY in glue/ — hidden dirs get stripped by some
# skill packagings, so the hidden layout of a source repo is only a fallback.
# A missing file degrades the install (no /harness command) but must not
# abort it.
mkdir -p "$target/.claude/commands" "$target/.opencode/command"
install_glue() {
  local visible="$1" hidden="$2"
  if [ -f "$SRC_ROOT/glue/$visible" ]; then
    cp "$SRC_ROOT/glue/$visible" "$target/$hidden"
  elif [ -f "$REPO_ROOT/$hidden" ]; then
    cp "$REPO_ROOT/$hidden" "$target/$hidden"
  else
    echo "WARN: $hidden not found (no glue/$visible either) — skipped (agent glue, optional)"
  fi
}
install_glue claude-command-harness.md   .claude/commands/harness.md
install_glue opencode-command-harness.md .opencode/command/harness.md
install_glue shellcheckrc                .shellcheckrc

if [ -f "$target/AGENTS.md" ]; then
  echo "WARN: $target/AGENTS.md exists — wrote AGENTS.harness.md instead; merge it manually"
  cp "$REPO_ROOT/AGENTS.md" "$target/AGENTS.harness.md"
else
  cp "$REPO_ROOT/AGENTS.md" "$target/AGENTS.md"
fi

sed -i "s|^# Agent Instructions (portable)|# Agent Instructions — ${name}|" \
  "$target/AGENTS.md" 2>/dev/null || true

# --- line endings --------------------------------------------------------------
# Gates are bash and parse frontmatter line by line. With Windows' default
# core.autocrlf=true, a CRLF checkout breaks every script ("pipefail\r: invalid
# option") and hides every approval marker. Pin LF for everything the gates read.
# Also normalise what we just copied, in case the skill itself arrived as CRLF.
find "$target/harness" -type f \( -name '*.sh' -o -name '*.yaml' -o -name '*.md' -o -name '*.template*' \) \
  -exec sed -i 's/\r$//' {} + 2>/dev/null || true

if ! grep -qs 'lean harness: keep LF' "$target/.gitattributes"; then
  cat >> "$target/.gitattributes" <<'EOF'

# lean harness: keep LF — gates are bash and parse these files line by line
harness/** text eol=lf
*.feature text eol=lf
AGENTS.md text eol=lf
.claude/commands/*.md text eol=lf
.opencode/command/*.md text eol=lf
EOF
fi

# --- git ----------------------------------------------------------------------
if [ "$do_git" -eq 1 ]; then
  if [ -d "$target/.git" ]; then
    echo "INFO: $target is already a git repo; skipping git init"
  else
    git -C "$target" init -q -b main
    echo "INFO: initialised git repo"
  fi
  if ! grep -qsxF '.claude/settings.local.json' "$target/.gitignore"; then
    cat >> "$target/.gitignore" <<'EOF'

# Claude Code local machine-specific settings
.claude/settings.local.json
EOF
  fi
  git -C "$target" add -A
  if git -C "$target" diff --cached --quiet; then
    echo "INFO: nothing to commit"
  else
    git -C "$target" commit -q -m "chore: scaffold lean harness

Phase machine: discover → architect → model → plan → ⟳(design → implement → verify) → release
Gates are pure checks; approval and phase transitions belong to the user."
    echo "INFO: initial commit created"
  fi
fi

cat <<EOF

harness installed in $target

  next: open the project and run /harness  (or: bash harness/gates/discover.sh)

  state:    harness/status.yaml       (phase: discover, nothing approved yet)
  contract: harness/workflow.yaml
  fill in:  harness/docs/prd.md       — the discover gate checks it
            harness/project.yaml      — test/lint/acceptance commands for YOUR stack

  approve an artifact:  say so in chat — the agent then writes
                        'approved_by: user' into the artifact itself
  advance a phase:      bash harness/gates/advance.sh <phase>
EOF

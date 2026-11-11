#!/usr/bin/env bash
# Consistency checks for THIS repo — the things that drifted before and that
# no gate self-test can see, because they are about the repo, not a project.
#
#   1. Tombstones: a concept the harness removed must not still be taught.
#      After meta-0004 dropped the sha256 sign-off, four separate commits were
#      needed to find the places that still described it; one of them was the
#      footer of the page a reviewer looks at.
#   2. Glue parity: the /harness commands this repo uses are hand-copied from
#      harness/glue/ (init.sh refuses to install into its own source repo).
#   3. Version bookkeeping: the workflow version that is live must have an
#      accepted, user-approved meta ADR behind it (docs/WORKFLOW_CHANGES.md:
#      ADR, approval, THEN version bump).
#
#   bash tools/check-repo.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

failures=0
bad() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# --- 1. tombstones -------------------------------------------------------------
# History may name them: the meta ADRs and the changelog tell the story of what
# was removed. The skill assets are a generated mirror (sync-skill.sh --check
# covers them), the vendored library is not ours, and this file has to spell
# the terms out to look for them.
TOMBSTONES='signoff\.sh|signed_off|SIGNOFF_AUTO|sha256|hash-verified|auto: true'

hits=$(git grep -nE "$TOMBSTONES" -- . \
  ':!harness/docs/adrs/meta-*.md' \
  ':!harness/docs/WORKFLOW_CHANGES.md' \
  ':!skills/harness-init/assets' \
  ':!skills/mermaid-render/vendor' \
  ':!tools/check-repo.sh' || true)
if [ -n "$hits" ]; then
  bad "removed concepts are still referenced outside the ADR history:"
  echo "$hits" >&2
fi

# --- 2. glue parity ------------------------------------------------------------
check_pair() {
  local src="$1" installed="$2"
  [ -f "$src" ] || { bad "missing $src"; return 0; }
  [ -f "$installed" ] || { bad "missing $installed (copy it from $src)"; return 0; }
  cmp -s "$src" "$installed" || bad "$installed differs from $src — copy the glue file over it"
}
check_pair harness/glue/claude-command-harness.md   .claude/commands/harness.md
check_pair harness/glue/opencode-command-harness.md .opencode/command/harness.md
check_pair harness/glue/shellcheckrc                .shellcheckrc

# --- 3. version bookkeeping ----------------------------------------------------
frontmatter_field() {
  awk -v field="$2" '
    { sub(/\r$/, "") }
    /^---$/ { if (in_fm) exit; in_fm = 1; next }
    in_fm && index($0, field ":") == 1 {
      val = substr($0, length(field) + 2)
      sub(/#.*$/, "", val)
      gsub(/^[ \t]+|[ \t]+$/, "", val)
      print val
      exit
    }
  ' "$1"
}

CHANGELOG=harness/docs/WORKFLOW_CHANGES.md
version=$(awk '/^version:/ { print $2; exit }' harness/workflow.yaml)
row=$(grep -m1 -E "^\|[[:space:]]*${version}[[:space:]]*\|" "$CHANGELOG" || true)

if [ -z "$row" ]; then
  bad "workflow.yaml is at version $version but $CHANGELOG has no row for it"
elif [[ "$row" =~ (meta-[0-9]{4}) ]]; then
  adr_id="${BASH_REMATCH[1]}"
  adr=""
  for f in harness/docs/adrs/"$adr_id"-*.md; do
    [ -e "$f" ] && adr="$f"
  done
  if [ -z "$adr" ]; then
    bad "version $version names $adr_id but harness/docs/adrs/ has no such ADR"
  else
    status=$(frontmatter_field "$adr" status)
    who=$(frontmatter_field "$adr" approved_by)
    case "$status" in
      accepted*|"partially superseded"*) ;;
      *) bad "workflow version $version is live, but $adr has status '$status' — a meta ADR takes effect when the user approves it, not before" ;;
    esac
    case "$who" in
      user|"user "*) ;;
      *) bad "workflow version $version is live, but $adr carries no 'approved_by: user'" ;;
    esac
  fi
  case "$row" in
    *proposed*) bad "$CHANGELOG still lists version $version as proposed" ;;
  esac
else
  bad "the $CHANGELOG row for version $version names no meta ADR"
fi

if [ "$failures" -gt 0 ]; then
  echo "RESULT: $failures repo check(s) failed" >&2
  exit 1
fi
echo "PASS: repo is consistent (no tombstones, glue in sync, version $version has an approved ADR)"

#!/usr/bin/env bash
# What happened while I was away? Pure, read-only — no state mutation.
#
# Collects what is already written, since autopilot was last switched on (or
# from the start, if it never was): the autopilot state, the transitions from
# audit/ with how each one happened, the decisions and whether they are
# answered, the iteration notes, the commits since the tripwire's base, and the
# current next.sh verdict. No new state; it only reads (meta-0009).
#
# Usage: bash gates/report.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="report"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

since=$(autopilot_field enabled_at)
[ "$since" = "null" ] && since=""
# Audit file names carry a compact UTC timestamp; compare in that form.
since_key=""
[ -n "$since" ] && since_key=$(printf '%s' "$since" | tr -d ':-')

section() { printf '\n## %s\n\n' "$1"; }

echo "# Harness report"
echo
echo "- **phase**: $(yq '.current_phase' "$STATUS_FILE")"
echo "- **iteration**: $(current_iteration | sed 's/^$/-/')"
echo "- **since**: ${since:-the beginning (autopilot was never switched on)}"

section "Autopilot"
print_autopilot_status | sed 's/^/    /'

section "Transitions"
found=0
if [ -d "$AUDIT_DIR" ]; then
  # "<timestamp> <file>" per entry, sorted by time across all gate names.
  while read -r key f; do
    [ -n "$f" ] || continue
    if [ -n "$since_key" ] && [[ "$key" < "$since_key" ]]; then
      continue
    fi
    title=$(sed -n '1{s/^# Audit: //;p;}' "$f")
    via=$(sed -n 's/^- \*\*transition via\*\*: //p' "$f")
    echo "- $key — $title${via:+ — via $via}"
    found=1
  done < <(for f in "$AUDIT_DIR"/*.md; do
             [ -e "$f" ] || continue
             n=$(basename "$f" .md)
             printf '%s %s\n' "${n##*-}" "$f"
           done | sort)
fi
[ "$found" -eq 1 ] || echo "(none)"

section "Decisions"
found=0
if [ -d "$DECISIONS_DIR" ]; then
  for d in "$DECISIONS_DIR"/DEC-*.md; do
    [ -e "$d" ] || continue
    who=$(approved_by_of "$d")
    title=$(sed -n '/^# /{s/^# //;p;q;}' "$d")
    if approval_is_valid "$who"; then
      echo "- answered ($who): $title"
    else
      echo "- OPEN: $title — $(rel_to_root "$d")"
    fi
    found=1
  done
fi
[ "$found" -eq 1 ] || echo "(none)"

section "Notes from the iterations"
found=0
cur=$(current_iteration)
while read -r id; do
  [ -n "$id" ] || continue
  f="$DOCS_DIR/iterations/${id}.md"
  if [ -f "$f" ]; then
    notes=$(awk '
      { sub(/\r$/, "") }
      /^## Notes/ { inn=1; next }
      /^## / && inn { inn=0 }
      inn && !/^<!--/ && !/^[[:space:]]*-->/ && !/^     / && NF
    ' "$f")
    if [ -n "$notes" ]; then
      echo "### $id"
      echo
      echo "$notes"
      echo
      found=1
    fi
  fi
  [ "$id" = "$cur" ] && break
done < <(plan_iteration_ids)
[ "$found" -eq 1 ] || echo "(none)"

section "Commits"
base=$(tripwire_base)
if [ -n "$base" ] && tripwire_available \
   && git -C "$HARNESS_ROOT" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  log=$(git -C "$HARNESS_ROOT" log --oneline "${base}..HEAD" 2>/dev/null || true)
  echo "${log:-(none since ${base:0:7})}"
else
  echo "(no base commit recorded — commits are not listed)"
fi

section "Now"
set +e
bash "$SCRIPT_DIR/next.sh" 2>&1 | sed 's/^/    /'
set -e

#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh plan.
#
# The plan slices the signed-off stories into iterations. Its frontmatter is the
# single source of truth for which iterations exist and what each delivers.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="plan"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

STORIES_DIR="$DOCS_DIR/user_stories"

require_gate_passed model

[ -f "$PLAN_FILE" ] || fail "missing $PLAN_FILE"

mapfile -t iters < <(plan_iteration_ids)
[ "${#iters[@]}" -gt 0 ] \
  || fail "plan.md frontmatter has no 'iterations:' entries"

max_iters=$(hardcap max_iterations)
[ "${#iters[@]}" -le "$max_iters" ] \
  || fail "iteration count ${#iters[@]} exceeds hardcap $max_iters"

# Collect every story the plan claims to cover, validating each iteration.
covered=""
seen=""
for id in "${iters[@]}"; do
  [[ "$id" =~ ^ITER-[0-9]{2,}$ ]] \
    || fail "iteration id '$id' does not match ITER-NN"
  case " $seen " in
    *" $id "*) fail "duplicate iteration id '$id' in plan.md" ;;
  esac
  seen="$seen $id"

  goal=$(plan_iteration_field "$id" "goal")
  [ -n "$goal" ] && [ "$goal" != "null" ] || fail "$id has no 'goal' in plan.md"

  mapfile -t stories < <(plan_iteration_field "$id" "stories[]")
  [ "${#stories[@]}" -gt 0 ] || fail "$id lists no stories in plan.md"

  for s in "${stories[@]}"; do
    [ -n "$(find "$STORIES_DIR" -maxdepth 1 -name "${s}*.md" -print -quit 2>/dev/null)" ] \
      || fail "$id references story '$s' but no $STORIES_DIR/${s}*.md exists"
    covered="$covered $s"
  done
done

# Every signed-off story must land in some iteration — otherwise it would be
# specified and approved but never built.
while read -r story; do
  [ -n "$story" ] || continue
  sid=$(frontmatter_value "$story" "id")
  [ -n "$sid" ] || fail "$story has no 'id' in frontmatter"
  case " $covered " in
    *" $sid "*) ;;
    *) fail "story $sid ($story) is not covered by any iteration in plan.md" ;;
  esac
done < <(find "$STORIES_DIR" -maxdepth 1 -name 'US-*.md' | sort)

require_signed_off "$PLAN_FILE"

pass

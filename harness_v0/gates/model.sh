#!/usr/bin/env bash
# Pure check — no state mutation. Advance via gates/advance.sh model.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_NAME="model"
# shellcheck source=_lib.sh
. "$SCRIPT_DIR/_lib.sh"

UML_DIR="$DOCS_DIR/uml"
ARCH="$DOCS_DIR/architecture.md"

require_gate_passed architect

[ -d "$UML_DIR" ] || fail "missing $UML_DIR"

# Every diagram must carry a sources line that references at least one
# upstream artifact: a story (US-n), an ADR (ADR-n / 000n), or a doc section.
check_sources() {
  local f="$1"
  head -10 "$f" | grep -q "^%% sources:" \
    || fail "$f missing '%% sources:' traceability frontmatter"
  head -10 "$f" | grep -E "^%% sources:" \
    | grep -Eq "US-[0-9]+|ADR-?[0-9]+|000[0-9]|prd\.md|architecture\.md" \
    || fail "$f '%% sources:' references no upstream artifact (US-n, ADR-n, prd.md, architecture.md)"
}

for level in c4-context c4-container c4-component; do
  f="$UML_DIR/${level}.mmd"
  [ -f "$f" ] || fail "missing $f"
  check_sources "$f"
done

grep -qF "uml/c4-context.mmd" "$ARCH" || fail "architecture.md does not link uml/c4-context.mmd"
grep -qF "uml/c4-container.mmd" "$ARCH" || fail "architecture.md does not link uml/c4-container.mmd"
grep -qF "uml/c4-component.mmd" "$ARCH" || fail "architecture.md does not link uml/c4-component.mmd"

mapfile -t seqs < <(find "$UML_DIR" -maxdepth 1 -name 'sequence-*.mmd' | sort)
[ "${#seqs[@]}" -gt 0 ] || fail "no sequence-*.mmd diagrams found"

mapfile -t states < <(find "$UML_DIR" -maxdepth 1 -name 'state-*.mmd' | sort)
[ "${#states[@]}" -gt 0 ] || fail "no state-*.mmd diagrams found"

for f in "${seqs[@]}" "${states[@]}"; do
  check_sources "$f"
done

pass

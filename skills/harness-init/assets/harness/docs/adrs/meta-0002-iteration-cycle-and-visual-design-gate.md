---
id: meta-0002
status: accepted
date: 2026-07-29
references:
  - WORKFLOW_CHANGES.md
  - meta-0001-pure-gates-and-verifiable-signoff.md
---

# meta-0002 Iteration cycle, visual design gate, and portable scaffolding

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`).

## Context and Problem Statement

v2 ran once, linearly, and ended in a dead end (`verify.next: null`): a second
delivery round meant resetting state by hand. It also had no step where a human
could *see* a design before it was built — diagrams existed as `.mmd` text that
nobody rendered. And there was no way to get the harness into a new project
except copying files and manually clearing state, which invites carrying the old
project's stories, sign-offs, and audit trail into the new one.

## Decision Drivers

- Real projects deliver in iterations, not one pass.
- Approving a design you have not looked at is not review.
- The trust model from meta-0001 must survive scaffolding: a fresh project must
  start with *zero* sign-offs.
- What we develop must be exactly what gets scaffolded — no second copy that
  drifts.

## Considered Options

1. **No change** — keep the linear one-shot workflow; handle repeat rounds by
   manually resetting `status.yaml`.
2. **Iteration counter only** — let `verify` loop back to `implement` with a
   counter in `status.yaml`, no plan and no design phase.
3. **Plan + iteration cycle + visual design gate + installer** — add `plan`
   (slice stories into iterations, gate enforces that every story is covered),
   make `design`/`implement`/`verify` iteration-scoped, add `release` as the
   project-level close, and ship an `init.sh` plus a personal skill that
   scaffolds the harness into any project.

## Decision Outcome

Chosen option: 3.

Option 1 keeps a known dead end. Option 2 loops but leaves the two real gaps:
nothing decides *what* an iteration contains (so stories can silently go
unbuilt), and nothing forces a reviewable design before implementation.

Key sub-decisions:

- **The iteration list lives in `docs/plan.md` frontmatter**, not in
  `status.yaml`. The plan is user-signed-off and is the source of truth for what
  the iterations *are*; `status.yaml` only tracks which one is current and which
  of its gates passed. This keeps one authority per fact.
- **`plan.sh` enforces full story coverage** — every signed-off story must
  appear in some iteration. A story that is specified, approved, and then never
  built is exactly the failure this catches.
- **`design.sh` requires a rendered HTML whose embedded sha256 matches the
  current markdown.** Freshness is checked by content hash, not mtime: bash's
  `-nt` compares whole seconds here, so a render immediately after a write —
  the normal agent sequence — was falsely reported stale.
- **Rendering lives in a separate `mermaid-render` skill**, not in the gates.
  The gate checks that a review artifact exists and is current; how it was
  produced is not the gate's business.
- **`init.sh` ships inside the `harness-init` skill's assets**, mirroring the
  repo layout so the same script runs from either place. `tools/sync-skill.sh
  --check` fails CI if the two copies drift.

### Consequences

- Good: repeat delivery without manual state surgery; designs are approved
  against something a human can look at; a new project starts provably empty;
  one development copy, drift-checked.
- Bad: more phases to hold in your head (7 vs 5), and `plan.md` frontmatter must
  stay in sync with its own human-readable table — the gate reads the
  frontmatter, so the table can silently drift (flagged `(manual)` in
  `dor_dod.yaml`).

### Confirmation

`bash harness/tests/gates/test_gates.sh` — 50 checks, including a full two-
iteration walk through `plan → design → implement → verify → design → … →
release`, story-coverage and duplicate-id rejection, stale-render detection, and
the meta-0001 regressions. Plus `shellcheck -x` and `tools/sync-skill.sh
--check`, all wired into CI.

## More Information

Changelog entry v3 in `WORKFLOW_CHANGES.md`. Supersedes nothing; extends
[meta-0001](meta-0001-pure-gates-and-verifiable-signoff.md), whose pure-gate and
hash-sign-off model is unchanged and now also covers `plan.md` and each
iteration's design.

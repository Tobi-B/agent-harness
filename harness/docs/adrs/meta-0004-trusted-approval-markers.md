---
id: meta-0004
status: accepted
date: 2026-08-17
references:
  - meta-0001-pure-gates-and-verifiable-signoff.md
  - meta-0003-bounded-autopilot.md
supersedes: meta-0001 (sign-off registry only — pure gates and advance flow stand)
---

# meta-0004 Trusted approval markers instead of the hash registry

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`).

## Context and Problem Statement

meta-0001 made approvals tamper-evident: the user ran `gates/signoff.sh`,
which recorded the artifact's sha256 in a registry in `status.yaml`, and gates
failed on any hash mismatch. In practice this ceremony cost more than it
protected: the user had to leave the conversation and run a script per
artifact (twice per story), every legitimate edit — a typo fix after approval —
invalidated the sign-off and forced a re-run, and the agent needed a special
`--auto` path just to let autopilot work. The user asked for approval to be
what it naturally is in a conversation: they say "approved", and that is the
record.

## Decision Drivers

- Approval friction was the single biggest ceremony cost in the loop.
- The harness is used in agent-driven sessions where the user's word in chat
  IS the primary act of approval; the script run was a re-enactment of it.
- Gates should stay executable shell scripts (unchanged requirement).
- It must remain *visible* what a human approved and what a machine did.

## Considered Options

1. Keep the hash registry (meta-0001 unchanged).
2. Registry without hashes — keep `signoff.sh`, drop the sha256.
3. **Approval markers in the artifacts themselves** — drop `signoff.sh` and
   the registry. An artifact is approved when it carries
   `approved_by: <who>` in its frontmatter (or a `# approved_by:` comment in
   `.feature` files). The agent writes the marker, but only after the user
   approved in conversation. Gates check only that the marker exists.

## Decision Outcome

Chosen option: 3. Option 2 keeps the script ceremony while giving up the only
thing the registry was for (tamper evidence), so it is the worst of both.
Option 3 accepts openly that the record is trust-based and moves the honesty
obligation into the agent instructions (`AGENTS.md`), where agent behavior is
governed anyway.

### Consequences

- Good: approval is one sentence in chat; edits after approval no longer
  invalidate anything mechanically (the agent must re-ask on *material*
  changes — an instruction, not a mechanism); autopilot needs no special
  code path (`approved_by: autopilot`; its scope is defined in meta-0005).
- Bad: approvals are forgeable by a misbehaving agent — the marker is plain
  text. The audit files written by `advance.sh` still snapshot which
  artifacts carried which marker at each transition, so a forged approval is
  discoverable in review, not prevented.
- Unchanged: gates are pure `.sh` checks; `advance.sh` remains the only phase
  transition and still requires the user (or `--yes` on explicit instruction,
  or autopilot within budget).

### Confirmation

`bash harness/tests/gates/test_gates.sh` — the suite now tests the marker
checks (missing marker fails, marker passes, `.feature` comment form works)
instead of hash tampering.

## More Information

Changelog entry v5 in `WORKFLOW_CHANGES.md`. The design gate's render
freshness check also dropped its content hash — it now compares mtimes
(render must not be older than its source).

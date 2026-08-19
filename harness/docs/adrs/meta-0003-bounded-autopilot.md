---
id: meta-0003
status: partially superseded by meta-0005 (scope and enablement; budget, expiry, audit marking stand)
date: 2026-07-29
references:
  - WORKFLOW_CHANGES.md
  - meta-0001-pure-gates-and-verifiable-signoff.md
  - meta-0002-iteration-cycle-and-visual-design-gate.md
---

# meta-0003 Bounded autopilot for the iteration cycle

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`).

## Context and Problem Statement

The harness stops at every gate. That is right for the phases where the shape of
the system is decided, and increasingly wrong for the fifth iteration of routine
delivery work, where the human is doing little more than typing `y`. Approval
that has become reflex is not review — it wears out the very attention the gates
exist to spend.

At the same time, the trust model from meta-0001 says approvals must not be
forgeable by the agent. "Let the agent decide when it has permission" would
dissolve that in one step.

## Decision Drivers

- Long autonomous runs (e.g. under Claude Code's `/loop`) are only useful if the
  harness does not block on a human every few minutes.
- The decisions worth a human's attention are concentrated in `discover`,
  `architect`, `model`, `plan` and `release` — not in each iteration's grind.
- Autonomy that never ends is a liability: a forgotten switch is indistinguishable
  from no gate at all.
- The audit trail must never blur what a human read and what a machine waved
  through.

## Considered Options

1. **No change** — every gate always stops. Honest, but pushes users toward
   `--yes` on everything, which is worse: unbounded and unrecorded.
2. **Global auto-approve flag** — one boolean covering all phases until turned
   off. Simple, but it hands over the architecture decisions too, and a flag left
   on silently disables the whole harness.
3. **Bounded autopilot scoped to the iteration cycle** — a user-enabled mode
   covering only `design`/`implement`/`verify`, expiring on wall clock and capped
   in iterations, with auto-approvals marked as such in the registry.

## Decision Outcome

Chosen option: 3.

Option 1 does not solve the problem; users route around it. Option 2 gives away
exactly the approvals that justify the harness — the ADRs and the plan — and has
no natural end.

Key sub-decisions:

- **Scope is fixed in code, not configuration** (`AUTOPILOT_PHASES` in
  `_lib.sh`). A configurable scope would drift toward "all", one convenient
  exception at a time. `discover`, `architect`, `model`, `plan` and `release`
  are never in scope.
- **Two independent budgets: wall clock and iterations.** Either running out
  stops autopilot. Time alone fails when the agent is fast; iterations alone fail
  when it is stuck.
- **Enabling requires an interactive terminal** (`autopilot.sh on`, TTY-checked,
  same barrier `advance.sh` uses). This is a guardrail against an ordinary
  non-interactive agent session, not a security boundary — an operator with a
  shell can always defeat it. Stated plainly so nobody mistakes it for one.
- **Auto sign-offs are marked `auto: true` and attributed to
  `autopilot(<enabler>)`**, and only apply to `docs/iterations/ITER-*`. The
  registry therefore always answers "did a human actually read this?" — and the
  hash mechanism from meta-0001 is untouched, so an edited artifact still
  invalidates its approval whether it was signed by a human or by autopilot.
- **Budget is charged per iteration, on first auto-advance of any of its
  phases** — not at `design` — so handing over mid-cycle still costs one
  iteration rather than being free.

### Consequences

- Good: long unattended runs become possible without deleting the review model;
  the expensive human attention is spent where the irreversible decisions are;
  every auto-approval is legible afterwards in `status.yaml` and the audit files.
- Bad: two approval paths now exist, so anyone reading the registry must notice
  the `auto` flag; and a user who enables autopilot habitually gets a harness
  that reviews iteration designs no more carefully than `--yes` would. The
  budgets make that a recurring decision rather than a permanent one, which is
  the mitigation, not a fix.

### Confirmation

`bash harness/tests/gates/test_gates.sh` — autopilot cases cover: off by
default; non-interactive enable refused; `--auto` refused outside the iteration
cycle; `--auto` refused when expired or out of budget; budget charged once per
iteration; `advance.sh` blocked non-interactively when autopilot is off and
proceeding when it is on; audit and registry record the auto attribution.

## More Information

Changelog entry v4 in `WORKFLOW_CHANGES.md`. Extends meta-0001; the sign-off
registry and hash verification are unchanged.

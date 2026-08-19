---
id: meta-0005
status: accepted
date: 2026-08-17
references:
  - meta-0003-bounded-autopilot.md
  - meta-0004-trusted-approval-markers.md
supersedes: meta-0003 (scope and enablement — budget, expiry and audit marking stand)
---

# meta-0005 Auto mode covers everything except release, enabled from chat

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`).

## Context and Problem Statement

meta-0003 introduced autopilot for the iteration cycle only
(`design`/`implement`/`verify`) and required an interactive terminal to
enable it, so an agent could not grant itself autonomy. After meta-0004 moved
approvals to trust-based markers, that asymmetry stopped making sense: the
agent is already trusted to write `approved_by: user` honestly, but was still
mechanically barred from flipping a switch the user asked for in chat. The
user's intent is a clean two-mode model: **without auto, a human-in-the-loop
development cycle; with auto, no human in the loop** — not a partial
delegation of three phases.

## Decision Drivers

- The mode split should be understandable in one sentence: auto off = human
  approves everything; auto on = agent runs alone.
- Sessions are conversational; "enable auto" said in chat IS the user acting.
- Some human checkpoint must survive even a fully auto run.
- Runaway protection must stay mechanical (trust covers honesty, not hangs).

## Considered Options

1. No change — keep the iteration-cycle-only autopilot with terminal-gated
   enablement (meta-0003).
2. Full autonomy including release — one switch, nothing waits for a human.
3. **Auto covers every phase except `release`; enabling is a chat
   instruction** — the agent runs `autopilot.sh on` when, and only when, the
   user explicitly asks. Expiry and iteration budget remain as the emergency
   brake. Auto-approved artifacts are marked `approved_by: autopilot`.

## Decision Outcome

Chosen option: 3. Option 2 removes the last human checkpoint from a process
whose entire purpose is gated delivery; keeping `release` human means an auto
run can build everything but a person still ships it. Option 1 keeps ceremony
the user explicitly asked to drop.

### Consequences

- Good: one honest dial instead of a partial one; the user can hand over an
  entire project run in one sentence and still owns the ship decision;
  autopilot enablement no longer needs terminal tricks in agent sessions.
- Bad: under auto, load-bearing decisions (ADRs, plan) are made by the agent
  and only marked `approved_by: autopilot` — the user reviews them after the
  fact via the audit trail and markers, not before. The budget and expiry
  bound how far that can run.
- Unchanged: gates still have to pass in order; `advance.sh` remains the only
  transition; auto attribution (`autopilot(<user>)` in audits,
  `approved_by: autopilot` in artifacts) keeps machine work distinguishable.

### Confirmation

`bash harness/tests/gates/test_gates.sh` — the suite checks that autopilot
enables without a terminal, that `release` is never in scope, and that budget
and expiry still shut it down.

## More Information

Changelog entry v6 in `WORKFLOW_CHANGES.md`.

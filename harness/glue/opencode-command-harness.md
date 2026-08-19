---
description: Drive the lean-harness development loop — read state, work the current phase, run its gate
---

# /harness — work the current phase of the lean harness

This repo uses the lean harness: a phase machine with executable gates and
user-approved artifacts. Full agent contract: `AGENTS.md` (root) and
`harness/workflow.yaml`. Do this now:

1. **Read the state.** `harness/status.yaml` → `current_phase`,
   `current_iteration`, autopilot. `harness/workflow.yaml` → what the phase
   produces and what its gate checks. `harness/dor_dod.yaml` → readiness
   criteria. Past `plan`, also read `harness/docs/plan.md` (iteration list).

2. **Locate where you stand.** Run the current phase's gate:
   `bash harness/gates/<phase>.sh` — pure check, safe to run anytime. Tell the
   user the phase, what the gate says, and what is missing.

3. **Work the phase.** Interview → draft → render (Mermaid designs via the
   `mermaid-render` skill; show the page before asking for approval) → ask the
   user to approve.

4. **Record approvals honestly.** An artifact is approved when it carries
   `approved_by: user` in its frontmatter (`# approved_by: user` comment in
   `.feature` files). Write that marker ONLY after the user explicitly
   approved that artifact in this conversation — never pre-fill it, never
   infer it from silence. On material edits after approval: re-ask first.

5. **Advance only with the user.** `bash harness/gates/advance.sh <phase>` is
   the user's action; pass `--yes` only when they explicitly told you to
   advance. Never advance past a failing gate.

Auto mode: off = human-in-the-loop cycle (the above). If the user explicitly
asks for auto mode, run `bash harness/gates/autopilot.sh on [--expires 8h]
[--max-iterations 3]` for them — then every phase except `release` runs
without asking, artifacts get `approved_by: autopilot`, and expiry/budget are
the emergency brake. `release` always waits for the user. Never enable auto
on your own initiative.

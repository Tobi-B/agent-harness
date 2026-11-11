---
description: One tick of the lean-harness loop — ask next.sh what now, do that one thing, stop when it is the user's move
---

# /harness — one tick of the lean harness

This repo uses the lean harness: a phase machine with executable gates and
user-approved artifacts. The rules are in `AGENTS.md` (root) — read it; the
contract is `harness/workflow.yaml`. This command is ONE tick, so it can be
run by hand or in a loop (`/loop /harness`). Do this now:

1. **Ask what now.** `bash harness/gates/next.sh` — pure. It prints the phase,
   the iteration, the gate's verdict, the autopilot state, one `action`, and
   what is waiting for the user. Its exit code: 0 go on, 3 the user's move,
   4 done, 2 environment broken.

2. **Do exactly that action.**
   - `work` — one unit of work on what the gate reports missing
     (`harness/dor_dod.yaml` lists the phase's criteria), then commit. Draft
     phases: interview → draft → render (Mermaid via the `mermaid-render`
     skill) → show it → ask for approval. In `implement`, one unit is one
     story — give each story a fresh subagent where the tool has them; a
     subagent never writes an approval marker and never runs `advance.sh`.
     `unattended: no` means: fine in conversation with the user, but in a
     loop, stop here.
   - `advance` — run the command it prints (`advance.sh`, no `--yes`), commit.
   - `approve` — only in auto mode `full`: mark what you drafted
     `approved_by: autopilot`.
   - `await_human` — show the user what is waiting (the rendered design, the
     decision file, the transition that is theirs) and STOP. Do not work
     around it.
   - `done` — the release has passed. Stop.

3. **Record approvals honestly.** An artifact is approved when it carries
   `approved_by: user` in its frontmatter (`# approved_by: user` comment in
   `.feature` files). Write that marker ONLY after the user explicitly
   approved that artifact in this conversation — never pre-fill it, never
   infer it from silence. On material edits after approval: re-ask first.

4. **Ask instead of guessing.** A question that is not yours to answer — an
   approved artifact would have to change, an architectural choice no ADR
   covers, a story that cannot be built as written, a `project.yaml` command
   would change, a hardcap, anything irreversible — becomes
   `harness/docs/decisions/DEC-NNN-<slug>.md`
   (`harness/templates/decision.template.md`) with an empty `approved_by:`.
   The machine then waits for the user. Small reversible choices go into the
   iteration's `## Notes`.

5. **Project commands.** From `architect` on, `harness/project.yaml` must name
   the real test / lint / acceptance commands for this stack (confirm with the
   user). Never stub one with `true` to get past the `implement` gate.

6. **Transitions.** `bash harness/gates/advance.sh <phase>` is the user's
   action unless `next.sh` said `advance`; pass `--yes` only when they
   explicitly told you to advance that phase. Never advance past a gate that
   does not pass.

Auto mode is the user's switch. Only if they explicitly ask, run
`bash harness/gates/autopilot.sh on [--mode build|full] [--expires 8h]
[--max-iterations 3]` for them. `build` (default): you carry the transitions
of `design`/`implement`/`verify` and approve nothing — every design still
needs the user. `full` (only if they named it): you also approve your own
drafts as `approved_by: autopilot`. `release` always waits for the user.

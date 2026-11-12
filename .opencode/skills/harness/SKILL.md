---
name: harness
description: |
  Lean documentation-driven agent workflow with executable gates. The agent
  reads workflow.yaml, runs one phase at a time, and only advances when the user
  approves. Load this skill when (a) the user wants to start or continue a
  harness project, (b) the user asks to add or change any artifact under
  harness/docs/, or (c) the user asks to review the workflow state.
---

# Harness

You are running inside the **lean harness** workflow. The contract lives in
`harness/workflow.yaml`. Read it first; treat it as the only source of truth for
phases, gates, and hardcaps.

## How to start

1. Locate `harness/workflow.yaml`. If missing, ask the user before scaffolding
   anything (`harness-init` skill, or `bash harness/init.sh <target>`).
2. Run `bash harness/gates/next.sh` — phase, iteration, the gate's verdict,
   the autopilot state, one action, and what is waiting for the user. Pure.
   (State lives in `harness/status.yaml`; approvals are *not* in there: they
   are `approved_by:` markers inside the artifacts themselves.)
3. Read `harness/dor_dod.yaml` for the phase's readiness checklist.
4. Read `harness/docs/plan.md` once past `plan` — it defines the iterations.
5. Do what `next.sh` says (see "the tick" below).

`AGENTS.md` at the repo root is the agent contract. Where this file and
`AGENTS.md` disagree, `AGENTS.md` wins.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

Per phase: **interview → draft → render → user_approves_in_chat → you_mark_approved_by → run_gate → advance**

- **interview** — targeted questions for the phase goal, a handful at a time.
- **draft** — write artifacts into the paths declared in `produces:`.
- **render** — in `model` and `design`, run the `mermaid-render` skill and show
  the user the page. Never request design approval without it.
- **user_approves_in_chat** — ask the user, plainly, to approve that artifact.
- **you_mark_approved_by** — only once they have, write `approved_by: user`
  into the artifact's frontmatter (or a `# approved_by: user` comment line in a
  `.feature` file). There is no hash and no registry: the gate checks only that
  the marker exists, so nothing but your own honesty stands between a real
  approval and a forged one. Never pre-fill it, never infer it from silence.
- **run_gate** — `bash harness/gates/<phase>.sh`. Pure checks, no side effects;
  run as often as useful. Exit 1 = work is missing, exit 3 = only the user's
  approval is missing. Fails twice for the same reason → escalate.
- **advance** — `bash harness/gates/advance.sh <phase>` is the user's, unless
  auto mode carries the phase (`next.sh` then says `action: advance`). Only
  pass `--yes` yourself if the user explicitly instructed you to advance.

## Auto mode, decisions, the tick

`AGENTS.md` holds these rules; this is the short form.

- **Auto mode** is enabled only on the user's explicit request:
  `bash harness/gates/autopilot.sh on [--mode build|full] [--expires 8h] [--max-iterations 3]`.
  Never enable it yourself and never edit the `autopilot` block in
  `status.yaml`.
  - `build` (default): you advance `design`, `implement`, `verify` without
    asking and approve **nothing** — every story, ADR, plan and iteration
    design still needs `approved_by: user`.
  - `full` (only if the user named it): you also mark what you drafted
    `approved_by: autopilot` — never `user` — in every phase except `release`.
- **Decisions.** A question that is not yours to answer (an approved artifact
  would change, an architectural choice no ADR covers, a story that cannot be
  built as written, a `project.yaml` command would change, a hardcap,
  anything irreversible) becomes `harness/docs/decisions/DEC-NNN-<slug>.md`
  with an empty `approved_by:`. While one is open, autopilot carries nothing
  and `release` does not pass. Small reversible choices go into the
  iteration's `## Notes`. If the answer changes a decided artifact, list it
  under the decision's `references:` — under autopilot, any other change to
  the PRD, plan, stories, features, ADRs or `project.yaml` trips the wire and
  stops the loop.
- **The tick.** `bash harness/gates/next.sh`, then: `work` → one unit, commit;
  `advance` → run the printed `advance.sh` command without `--yes`;
  `approve` (mode `full`) → mark your drafts `approved_by: autopilot`;
  exit 3 → show the user what is waiting and stop; exit 4 → done.

Gates still have to pass, and you still render designs and show them. Do not
work out for yourself whether auto mode covers a phase — `next.sh` says so.
`release` always waits for the user.

## Phase-specific reminders

### discover
- One story per acceptance criterion; template in `docs/user_stories/README.md`.
- Every story needs a 1:1 `harness/tests/features/US-*.feature`
  (skeleton: `harness/templates/feature.template`).
- Story **and** feature file each need an `approved_by:` marker.
- Respect `hardcaps.max_user_stories_per_discover_run`.

### architect
- Max `hardcaps.max_adrs_v0` ADRs (currently 3). `meta-*.md` are exempt.
- MADR template in `docs/adrs/README.md`; at least two options with tradeoffs
  before asking the user to decide.
- Update `docs/architecture.md` (C4 levels + Cross-Cutting Concerns).

### model
- Mermaid only, `.mmd` under `harness/docs/uml/`.
- Mandatory first line: `%% sources: <list>`, referencing at least one upstream
  artifact (US-n, ADR-n, prd.md, architecture.md) — the gate checks this.
- Render the diagrams and show them to the user before advancing.

### plan
- Slice stories into small **vertical** iterations, each delivering testable
  user value on its own.
- The frontmatter of `docs/plan.md` is what the gate reads:
  `iterations: [{id: ITER-01, goal: ..., stories: [US-001]}]`.
- **Every** approved story must be covered by some iteration; the gate
  rejects orphans. Keep the human-readable table in sync with the frontmatter.
- The plan needs an `approved_by:` marker.

### design (per iteration)
- Use `harness/templates/iteration.template.md` → `docs/iterations/ITER-NN.md`.
- Required sections: `## Goal`, `## Approach`, `## Affected Components`,
  `## Test Strategy`, plus a `## Verification` section for later.
- At least one mermaid block, and the file must name every story the plan
  assigned to this iteration.
- Render to `docs/iterations/ITER-NN.html` and **show it**. Until the design
  is approved the gate requires the HTML to be no older than the markdown, so
  re-render after any edit.
- The iteration design needs `approved_by: user` (`autopilot` counts only in
  auto mode `full`). The user may approve designs several iterations ahead.
- If an approved design no longer fits when its turn comes: open a decision,
  do not edit it.

### implement (per iteration)
- TDD: failing test first, then minimum code to pass. One story at a time —
  in a fresh subagent per story where the tool has them; a subagent never
  writes an approval marker and never runs `advance.sh`.
- The gate runs `commands.test|lint|acceptance` from `harness/project.yaml` in
  the **project root** (the directory containing `harness/`), and scans
  `source_dirs` for `TODO`/`FIXME` — comments included.
- A Python project with a `pyproject.toml` may leave those commands empty
  (pytest / ruff / behave are the fallback). Anything else must fill them in,
  or the gate fails. Missing source, an empty command, and a missing tool all
  FAIL; only the user may decide to set `allow_missing_tools: true` in
  `project.yaml` (the `HARNESS_ALLOW_MISSING_TOOLS=1` hatch is ignored under
  autopilot).
- Acceptance runs only the stories due so far: point the command at
  `$HARNESS_DUE_FEATURES`.

### verify (per iteration)
- Fill `## Verification` in the iteration file, reporting on **every** story of
  that iteration, and check off the items. Unchecked boxes fail the gate, and
  the gate runs test, lint and acceptance again — the boxes are your account,
  the commands the evidence.
- Advancing past `verify` either starts the next iteration's `design` or moves
  to `release` — the user decides when to advance, or auto mode does while it
  carries `verify`.

### release
- Measure NFRs, compare against PRD Success Criteria, check off every PRD
  checkbox, write `docs/verify-report.md` with `## Result`, `Success Criteria`,
  and `NFR` sections. Add a short retro.
- The gate runs test, lint and acceptance over every planned story.
- The gate fails while any decision is open, and the transition is always the
  user's.

## Hard rules

- Never edit `status.yaml` by hand — `advance.sh` and `autopilot.sh` own it.
- Never write `approved_by: user` before the user actually approved. The gate
  cannot detect a forged marker; that is why the rule is absolute.
- Never run `advance.sh --yes` without an explicit user instruction for that
  specific phase. Auto mode does not change this: under auto you run
  `advance.sh` without `--yes`.
- Never mark anything `approved_by: autopilot` unless auto mode is on in mode
  `full`.
- Never answer an open decision yourself.
- Never create a fourth project ADR without a decision from the user.
- Never materially edit an approved artifact without telling the user and
  re-requesting approval before restoring the marker.
- Never ask for design approval without showing the rendered diagram.
- Never assume the next phase — ask `next.sh`.

## When to escalate

Open a decision (above) for anything on the trigger list in `AGENTS.md`. Also
stop and tell the user when:

- a gate fails twice in a row for the same reason
- a request falls outside the PRD's declared scope
- a meta-question arises (`harness/docs/WORKFLOW_CHANGES.md` applies)

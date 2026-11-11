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
2. Read `harness/status.yaml` — `current_phase`, `current_iteration`, gate
   history, and the `autopilot` block. Approvals are *not* in here: they live
   as `approved_by:` markers inside the artifacts themselves.
3. Read `harness/dor_dod.yaml` for the phase's readiness checklist.
4. Read `harness/docs/plan.md` once past `plan` — it defines the iterations.
5. Run the current phase's gate. Confirm with the user which phase to work on —
   unless auto mode is on (see below), in which case the current phase is the
   one to work.

`AGENTS.md` at the repo root is the agent contract. Where this file and
`AGENTS.md` disagree, `AGENTS.md` wins.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

Per phase: **interview → draft → render → user_approves_in_chat → you_mark_approved_by → run_gate → user_advances**

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
  run as often as useful. Fails twice for the same reason → escalate.
- **user_advances** — ask the user to run
  `bash harness/gates/advance.sh <phase>`. Only pass `--yes` yourself if the
  user explicitly instructed you to advance.

## Auto mode — only if the user asked for it

The loop above is the human-in-the-loop mode. The user may instead ask for auto
mode; when — and only when — they explicitly do, run
`bash harness/gates/autopilot.sh on [--expires 8h] [--max-iterations 3]` for
them. Never enable it yourself and never edit the `autopilot` block in
`status.yaml`. Check it with `bash harness/gates/autopilot.sh status`.

While it is on, for every phase except `release`:

- mark artifacts you drafted `approved_by: autopilot` — never `user`;
- run `bash harness/gates/advance.sh <phase>` without `--yes`: it proceeds
  without the prompt and spends the iteration budget.

Gates still have to pass, and you still render designs and leave them for the
user. If auto mode is off, expired or out of budget, stop and say so — do not
reach for `--yes`. `release` always waits for the user.

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
- Render to `docs/iterations/ITER-NN.html` and **show it**. The gate requires
  the HTML to be no older than the markdown, so re-render after any edit.
- The iteration design needs an `approved_by:` marker.

### implement (per iteration)
- TDD: failing test first, then minimum code to pass.
- The gate runs `commands.test|lint|acceptance` from `harness/project.yaml` in
  the **project root** (the directory containing `harness/`), and scans
  `source_dirs` for `TODO`/`FIXME` — comments included.
- A Python project with a `pyproject.toml` may leave those commands empty
  (pytest / ruff / behave are the fallback). Anything else must fill them in,
  or the gate fails. Missing source, an empty command, and a missing tool all
  FAIL; only the user may decide to set `HARNESS_ALLOW_MISSING_TOOLS=1`.

### verify (per iteration)
- Fill `## Verification` in the iteration file, reporting on **every** story of
  that iteration, and check off the items. Unchecked boxes fail the gate.
- Advancing past `verify` either starts the next iteration's `design` or moves
  to `release` — the user decides when to advance, or auto mode does while it
  is on.

### release
- Measure NFRs, compare against PRD Success Criteria, check off every PRD
  checkbox, write `docs/verify-report.md` with `## Result`, `Success Criteria`,
  and `NFR` sections. Add a short retro.

## Hard rules

- Never edit `status.yaml` by hand — `advance.sh` and `autopilot.sh` own it.
- Never write `approved_by: user` before the user actually approved. The gate
  cannot detect a forged marker; that is why the rule is absolute.
- Never run `advance.sh --yes` without an explicit user instruction for that
  specific phase. Auto mode does not change this: under auto you run
  `advance.sh` without `--yes`.
- Never create a fourth project ADR without escalating.
- Never materially edit an approved artifact without telling the user and
  re-requesting approval before restoring the marker.
- Never ask for design approval without showing the rendered diagram.
- Never assume the next phase — ask, unless auto mode is on.

## When to escalate

- a gate fails twice in a row
- a fourth ADR is needed
- a request falls outside the PRD's declared scope
- the PRD must change after stories are approved
- a meta-question arises (`harness/docs/WORKFLOW_CHANGES.md` applies)

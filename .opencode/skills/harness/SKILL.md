---
name: harness
description: |
  Lean documentation-driven agent workflow with executable gates. The agent
  reads workflow.yaml, runs one phase at a time, and only advances when the user
  signs off. Load this skill when (a) the user wants to start or continue a
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
   history, and the sign-off registry (`signed_off_artifacts`).
3. Read `harness/dor_dod.yaml` for the phase's readiness checklist.
4. Read `harness/docs/plan.md` once past `plan` — it defines the iterations.
5. Run the current phase's gate. Confirm with the user which phase to work on.
   Never assume.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

Per phase: **interview → draft → render → user_signs_off → run_gate → user_advances**

- **interview** — targeted questions for the phase goal, a handful at a time.
- **draft** — write artifacts into the paths declared in `produces:`.
- **render** — in `model` and `design`, run the `mermaid-render` skill and show
  the user the page. Never request design approval without it.
- **user_signs_off** — ask the user to run
  `bash harness/gates/signoff.sh <artifact>`. That records the file's sha256.
  YOU never run signoff.sh and never edit `signed_off_artifacts` — gates verify
  the hash, forged entries fail.
- **run_gate** — `bash harness/gates/<phase>.sh`. Pure checks, no side effects;
  run as often as useful. Fails twice for the same reason → escalate.
- **user_advances** — ask the user to run
  `bash harness/gates/advance.sh <phase>`. Only pass `--yes` yourself if the
  user explicitly instructed you to advance.

## Phase-specific reminders

### discover
- One story per acceptance criterion; template in `docs/user_stories/README.md`.
- Every story needs a 1:1 `harness/tests/features/US-*.feature`
  (skeleton: `harness/templates/feature.template`).
- Story **and** feature file each need sign-off.
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
- **Every** signed-off story must be covered by some iteration; the gate
  rejects orphans. Keep the human-readable table in sync with the frontmatter.
- The plan needs sign-off.

### design (per iteration)
- Use `harness/templates/iteration.template.md` → `docs/iterations/ITER-NN.md`.
- Required sections: `## Goal`, `## Approach`, `## Affected Components`,
  `## Test Strategy`, plus a `## Verification` section for later.
- At least one mermaid block, and the file must name every story the plan
  assigned to this iteration.
- Render to `docs/iterations/ITER-NN.html` and **show it**. The gate checks the
  embedded sha256 against the markdown, so re-render after any edit.
- The iteration design needs sign-off.

### implement (per iteration)
- TDD: failing test first, then minimum code to pass.
- No `TODO`/`FIXME` in delivered code (gate enforces).
- The gate FAILS if `pytest`/`ruff`/`behave` are needed but missing. Only the
  user may decide to set `HARNESS_ALLOW_MISSING_TOOLS=1`.

### verify (per iteration)
- Fill `## Verification` in the iteration file, reporting on **every** story of
  that iteration, and check off the items. Unchecked boxes fail the gate.
- Advancing past `verify` either starts the next iteration's `design` or moves
  to `release` — the user decides when to advance.

### release
- Measure NFRs, compare against PRD Success Criteria, check off every PRD
  checkbox, write `docs/verify-report.md` with `## Result`, `Success Criteria`,
  and `NFR` sections. Add a short retro.

## Hard rules

- Never run `signoff.sh`; never edit `status.yaml`. Sign-offs and transitions
  belong to the user.
- Never run `advance.sh --yes` without an explicit user instruction for that
  specific phase.
- Never create a fourth project ADR without escalating.
- Never edit a signed-off artifact without telling the user it invalidates the
  sign-off (hash mismatch) and re-requesting approval.
- Never ask for design approval without showing the rendered diagram.
- Never assume the next phase — always ask.

## When to escalate

- a gate fails twice in a row
- a fourth ADR is needed
- a request falls outside the PRD's declared scope
- the PRD must change after stories are signed off
- a meta-question arises (`harness/docs/WORKFLOW_CHANGES.md` applies)

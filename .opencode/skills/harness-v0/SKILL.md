---
name: harness-v0
description: |
  Lean documentation-driven agent workflow. The agent reads workflow.yaml, runs one
  phase at a time, and only advances past a gate when the user signs off. Load this
  skill when (a) the user wants to start or continue a harness_v0/ project,
  (b) the user asks to add or change any artifact under harness_v0/docs/, or
  (c) the user asks to review the workflow state.
---

# Harness v0

You are running inside the **lean harness v0** workflow. The contract lives in
`harness_v0/workflow.yaml`. Read it first; treat it as the only source of truth
for phases, gates, and hardcaps.

## How to start

1. Locate `harness_v0/workflow.yaml`. If missing, ask the user before
   scaffolding anything.
2. Read `harness_v0/dor_dod.yaml` for per-phase readiness checklists.
3. Read `harness_v0/status.yaml` to learn the current phase, gate history,
   and the sign-off registry (`signed_off_artifacts`).
4. Read every artifact under `harness_v0/docs/` to see what exists and what
   is signed off.
5. Confirm with the user which phase to work on. Never assume.

## The loop (every phase)

```
interview -> draft -> user_signs_off -> run_gate -> user_advances
```

For every phase:

- **interview** — ask the user targeted questions for the phase goal.
- **draft** — write the artifact into the path declared in `produces:`.
- **user_signs_off** — ask the user to approve and to run
  `bash harness_v0/gates/signoff.sh <artifact>`. That records the file's
  sha256 in `status.yaml`. YOU never run signoff.sh and never edit
  `signed_off_artifacts` — gates verify the hash, forged entries fail.
- **run_gate** — execute `bash harness_v0/gates/<phase>.sh`. Gates are pure
  checks (no side effects); run them as often as useful. If a gate fails,
  fix and retry; if it fails twice, escalate to the user.
- **user_advances** — when the gate passes, ask the user to run
  `bash harness_v0/gates/advance.sh <phase>` (writes the audit file, updates
  status.yaml, moves current_phase). Only pass `--yes` yourself if the user
  explicitly instructed you to advance.

## Phase-specific reminders

### discover

- One story per acceptance criterion. Use the template in
  `harness_v0/docs/user_stories/README.md`.
- Every story must have a matching Gherkin file under
  `harness_v0/tests/features/US-*.feature` (1:1). Skeleton:
  `harness_v0/templates/feature.template`.
- Stories must carry `references:` frontmatter linking to PRD sections.
- Both the story AND its feature file need sign-off (the gate checks both).
- Do not exceed `hardcaps.max_user_stories_per_discover_run`.

### architect

- Maximum `hardcaps.max_adrs_v0` ADRs (currently 3). No silent fourth.
  `meta-*.md` workflow ADRs are exempt from the cap.
- Use the MADR template (`docs/adrs/README.md`).
- Each ADR must list at least two options with tradeoffs before asking
  the user to decide.
- Update `harness_v0/docs/architecture.md` with the components each ADR
  implies (C4 levels + Cross-Cutting Concerns).

### model

- Mermaid only. MMD files under `harness_v0/docs/uml/`.
- Mandatory first line in every diagram: `%% sources: <list>` — and the list
  must reference at least one upstream artifact (US-n, ADR-n, prd.md,
  architecture.md); the gate checks this.
- Generate C4 (context → container → component → code where needed),
  plus one sequence diagram per key flow and one state diagram per
  lifecycle.
- `harness_v0/docs/architecture.md` must link each diagram.

### implement

- TDD: failing test first, then minimum code to pass.
- Do not leave `TODO` / `FIXME` in delivered code (gate enforces this).
- Use idempotency keys per `architecture.md` Cross-Cutting Concerns
  (review item — not machine-checked).
- The gate FAILS if `pytest` / `ruff` / `behave` are needed but missing.
  Only the user may decide to set `HARNESS_ALLOW_MISSING_TOOLS=1`.

### verify

- Run end-to-end against the PRD Success Criteria and NFRs.
- Check off each verified `- [x]` item in `prd.md`; the gate rejects
  remaining `- [ ]` boxes.
- Produce `harness_v0/docs/verify-report.md` with `## Result`,
  `Success Criteria`, and `NFR` sections.

## Hard rules

- Never run `signoff.sh` and never edit `status.yaml` yourself — sign-offs
  and phase transitions belong to the user (`signoff.sh` / `advance.sh`).
- Never run `advance.sh --yes` without an explicit user instruction to
  advance this specific phase.
- Never create a fourth project ADR without escalating to the user.
- Never edit a signed-off artifact without telling the user it invalidates
  the sign-off (hash mismatch) and re-requesting approval.
- Never assume the next phase — always ask.

## When to escalate

Stop and ask the user when:

- a gate fails twice in a row
- a fourth ADR is needed
- the user asks for something outside the declared scope of the PRD
- the PRD itself needs to change after stories are signed off
- a meta-question arises (`harness_v0/docs/WORKFLOW_CHANGES.md` applies)

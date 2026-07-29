# Workflow Changes (Meta-Loop)

Changes to `workflow.yaml`, `gates/`, `dor_dod.yaml`, or any template under `docs/` must go through this meta-process. They are not normal project work.

## Process

1. Open a discussion describing the change and why the current `workflow.yaml` shape is wrong for the new context.
2. Draft a new ADR under `docs/adrs/` titled `meta-NNNN-<slug>.md` using the standard MADR format (`docs/adrs/README.md`). The `meta-` prefix keeps it out of the project ADR hardcap: `gates/architect.sh` counts only `000*.md`.
3. The ADR's *Context* must reference which existing gate or phase is being changed.
4. The ADR's *Considered Options* must include **no change** as an explicit option.
5. Sign-off requires the same user who approved the original workflow (or an explicit delegation recorded in the ADR).
6. On sign-off:
   - bump `version:` in `workflow.yaml`
   - update `harness/README.md` if the file layout changed
   - commit with message `harness: meta ADR-NNNN <slug>`
   - add an entry under the *Changelog* section below

## What does NOT need this process

- Adding a new artifact under `harness/docs/` without changing gates.
- Adding new Gherkin scenarios to an existing `.feature` file.
- Adding a new diagram file under `harness/docs/uml/`.
- Updating `status.yaml` at phase boundaries.

Those are normal project work, governed by their respective phase gates.

## Changelog

| Version | Date | ADR | Summary |
|---|---|---|---|
| 0 | initial | — | 5-phase lean workflow, single source of truth in `workflow.yaml`. |
| 1 | | | Executable gates, MADR ADRs, C4 architecture, NFRs first-class, status file, audit trail, idempotency, meta-loop. |
| 2 | 2026-07-18 | meta-0001 | Gates are pure checks; hash-based user sign-off via `gates/signoff.sh`; phase transitions + audit via `gates/advance.sh`; enforced-only gate criteria; strict tool checks; gate self-tests, shellcheck, CI. |
| 3 | 2026-07-29 | meta-0002 | Iteration cycle: new `plan`, `design`, `release` phases; `design`/`implement`/`verify` are iteration-scoped and loop until the plan is exhausted. Visual design gate (rendered Mermaid, hash-checked freshness). `harness/init.sh` + `harness-init` skill for scaffolding; directory renamed `harness_v0/` → `harness/`. |

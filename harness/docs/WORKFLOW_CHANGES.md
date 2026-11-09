# Workflow Changes (Meta-Loop)

Changes to `workflow.yaml`, `gates/`, `dor_dod.yaml`, or any template under `docs/` must go through this meta-process. They are not normal project work.

## Process

1. Open a discussion describing the change and why the current `workflow.yaml` shape is wrong for the new context.
2. Draft a new ADR under `docs/adrs/` titled `meta-NNNN-<slug>.md` using the standard MADR format (`docs/adrs/README.md`). The `meta-` prefix keeps it out of the project ADR hardcap: `gates/architect.sh` counts only `000*.md`.
3. The ADR's *Context* must reference which existing gate or phase is being changed.
4. The ADR's *Considered Options* must include **no change** as an explicit option.
5. Approval requires the same user who approved the original workflow (or an explicit delegation recorded in the ADR).
6. On approval:
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
| 7 | 2026-09-21 | meta-0006 *(proposed)* | Silent-pass holes closed: approval allowlist (`user`/`autopilot`; drafts, placeholders and template comments no longer count); implement gate runs in the project root with commands from project-owned `project.yaml` (Python default kept), TODO scan includes comments, no source / empty command fails; `advance.sh` only advances the current phase; autopilot finishes claimed iterations; SIGPIPE race in `advance.sh plan` fixed; Windows LF via `.gitattributes` + CR-tolerant parsing; bash >= 4 check. |
| 6 | 2026-08-17 | meta-0005 | Auto mode widened: without auto the cycle is human-in-the-loop; with auto the agent runs every phase except `release` (which always waits for a human). Enabled from chat — the agent runs `autopilot.sh on` only on explicit user instruction; terminal requirement dropped. Expiry + iteration budget remain as the emergency brake. |
| 5 | 2026-08-17 | meta-0004 | Trusted approval markers: `gates/signoff.sh` and the sha256 registry removed. An artifact is approved when it carries `approved_by: <who>` (frontmatter, or `# approved_by:` comment in `.feature` files), written by the agent only after the user approved in conversation. Design-render freshness by mtime instead of embedded hash. Autopilot marks iteration designs `approved_by: autopilot`. |
| 0 | initial | — | 5-phase lean workflow, single source of truth in `workflow.yaml`. |
| 1 | | | Executable gates, MADR ADRs, C4 architecture, NFRs first-class, status file, audit trail, idempotency, meta-loop. |
| 2 | 2026-07-18 | meta-0001 | Gates are pure checks; hash-based user sign-off via `gates/signoff.sh`; phase transitions + audit via `gates/advance.sh`; enforced-only gate criteria; strict tool checks; gate self-tests, shellcheck, CI. |
| 4 | 2026-07-29 | meta-0003 | Bounded autopilot: `gates/autopilot.sh on/off/status` lets the user hand the iteration cycle (`design`/`implement`/`verify`) to the agent, capped by wall clock and iteration count. `signoff.sh --auto` records machine approvals as `auto: true`; `advance.sh` skips its prompt only inside that scope. `discover`, `architect`, `model`, `plan`, `release` always need a human. |
| 3 | 2026-07-29 | meta-0002 | Iteration cycle: new `plan`, `design`, `release` phases; `design`/`implement`/`verify` are iteration-scoped and loop until the plan is exhausted. Visual design gate (rendered Mermaid, hash-checked freshness). `harness/init.sh` + `harness-init` skill for scaffolding; directory renamed `harness_v0/` → `harness/`. |

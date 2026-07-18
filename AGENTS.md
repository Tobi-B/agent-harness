# Agent Instructions (portable)

This repo uses the **lean harness v0** workflow. The contract lives in `harness_v0/workflow.yaml`. This file is the portable summary that any agent (opencode, Aider, Cursor, Copilot, Continue, …) can read without opencode-specific setup. opencode-specific instructions live in `.opencode/skills/harness-v0/SKILL.md`.

## Quick Start

1. Read `harness_v0/workflow.yaml` to understand the phases and gates.
2. Read `harness_v0/dor_dod.yaml` for per-phase readiness criteria.
3. Read existing artifacts in `harness_v0/docs/` to understand signed-off state.
4. Read `harness_v0/status.yaml` to know the current phase.
5. Confirm with the user which phase to work on.

## Loop

```
interview -> draft -> user_signs_off -> run_gate -> user_advances
```

User approval is required for:

- phase transitions
- every ADR decision
- changes to signed-off artifacts
- exceptions to hardcaps

## Sign-off is the user's action, not yours

Approvals live in the sign-off registry in `harness_v0/status.yaml` (path + sha256 + by + at), written **only** by the user running `bash harness_v0/gates/signoff.sh <artifact>`. Do not run `signoff.sh` yourself and do not edit `signed_off_artifacts` — gates verify the recorded hash against the file's current content, so a forged or stale entry fails the gate. If you edit a signed-off artifact, tell the user it needs re-sign-off.

## Gates are executable and pure

Each phase's gate is a runnable script under `harness_v0/gates/`. Run them freely via `bash harness_v0/gates/<phase>.sh` — they are pure checks with no side effects. Do not advance if a gate fails.

Phase transitions happen only via `bash harness_v0/gates/advance.sh <phase>` (runs the gate, writes `harness_v0/audit/<phase>-<timestamp>.md`, updates `status.yaml`). The user runs it; you may pass `--yes` only when the user explicitly told you to advance.

## Traceability

Every artifact carries YAML frontmatter with `references:` to the artifacts it depends on. Use the syntax `references: [US-003, ADR-0001]`. The `model` gate verifies that every diagram's `%% sources:` line references at least one upstream artifact (US-n, ADR-n, `prd.md`, or `architecture.md`).

## Acceptance Criteria are Executable

Each user story has a 1:1 Gherkin file under `tests/features/`. The `implement` gate runs these. Do not skip writing them during `discover`. The skeleton lives at `harness_v0/templates/feature.template`.

## Status

`harness_v0/status.yaml` is the authoritative state. Gates never write it; `signoff.sh` and `advance.sh` do. Frontmatter `status:` fields in artifacts are informational only — the sign-off registry is the authority.

## Meta-loop

Changes to the harness itself go through `harness_v0/docs/WORKFLOW_CHANGES.md` (meta ADR `meta-NNNN-*.md`, user sign-off, version bump). Do not edit `workflow.yaml` ad-hoc.

## Tools

- `bash`, `jq`, mikefarah `yq` v4 — required for gates (the gate library rejects python-yq)
- `pytest`, `ruff` — required when `src/` exists (missing tools FAIL the implement gate unless `HARNESS_ALLOW_MISSING_TOOLS=1`)
- `behave` (or any Gherkin runner) — required for `tests/features/*.feature`

Install with `winget install MikeFarah.yq jqlang.jq` (Windows), `brew install yq jq` (macOS). Python tools via `pip install behave pytest pytest-bdd ruff`.

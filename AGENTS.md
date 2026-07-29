# Agent Instructions (portable)

This repo uses the **lean harness** workflow. The contract lives in
`harness/workflow.yaml`. This file is the portable summary that any agent
(opencode, Aider, Cursor, Copilot, Continue, …) can read without tool-specific
setup. Claude Code and opencode also have a `/harness` command.

## Quick Start

1. Read `harness/status.yaml` — `current_phase`, `current_iteration`, sign-offs.
2. Read `harness/workflow.yaml` — phases, gates, hardcaps.
3. Read `harness/dor_dod.yaml` — per-phase readiness criteria.
4. Read `harness/docs/plan.md` — the iteration list, once past `plan`.
5. Run the current phase's gate to see where you stand. Confirm with the user
   which phase to work on.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

`design`, `implement`, and `verify` are iteration-scoped: they run once per
iteration in `docs/plan.md` and record their state under
`iterations.<ITER-NN>` in `status.yaml`.

Per phase: **interview → draft → render → user signs off → run gate → user advances.**

User approval is required for: phase transitions, every ADR, every iteration
design, changes to signed-off artifacts, exceptions to hardcaps.

## Sign-off is the user's action, not yours

Approvals live in the sign-off registry in `harness/status.yaml` (path + sha256
+ by + at), written **only** by the user running
`bash harness/gates/signoff.sh <artifact>`. Do not run `signoff.sh` yourself and
do not edit `signed_off_artifacts` — gates verify the recorded hash against the
file's current content, so a forged or stale entry fails the gate. If you edit a
signed-off artifact, tell the user it needs re-sign-off.

## Gates are executable and pure

Each phase's gate is a runnable script under `harness/gates/`. Run them freely
via `bash harness/gates/<phase>.sh` — they are pure checks with no side effects.
Do not advance if a gate fails.

Phase and iteration transitions happen only via
`bash harness/gates/advance.sh <phase>` (runs the gate, writes
`harness/audit/<phase>-<timestamp>.md`, updates `status.yaml`). The user runs
it; you may pass `--yes` only when the user explicitly told you to advance.

## Show designs before asking for approval

In `model` and `design`, render the Mermaid diagrams to a page the user can
look at:

```bash
bash ~/.claude/skills/mermaid-render/render.sh -o <out>.html --title "<title>" <sources>
```

Then show it (`SendUserFile` with `display: "render"`). The `design` gate
requires a rendered HTML whose embedded sha256 matches the current markdown, so
a stale render fails. Never ask for design sign-off without showing the diagram.

## Traceability

Every artifact carries YAML frontmatter with `references:` to what it depends
on (`references: [US-003, ADR-0001]`). The `model` gate verifies that every
diagram's `%% sources:` line references at least one upstream artifact. The
`plan` gate verifies that every signed-off story is covered by some iteration.

## Acceptance Criteria are Executable

Each user story has a 1:1 Gherkin file under `harness/tests/features/`. The
`implement` gate runs them and requires one per story in the current iteration.
Skeletons live in `harness/templates/`.

## Status

`harness/status.yaml` is the authoritative state. Gates never write it;
`signoff.sh` and `advance.sh` do. Frontmatter `status:` fields are
informational — the sign-off registry is the authority. `docs/plan.md`
frontmatter is the authority on what the iterations are.

## Meta-loop

Changes to the harness itself (`workflow.yaml`, `gates/`, `dor_dod.yaml`,
templates) go through `harness/docs/WORKFLOW_CHANGES.md`: a `meta-NNNN-*.md`
ADR, user sign-off, version bump. Do not edit `workflow.yaml` ad-hoc.

## Tools

- `bash`, `jq`, mikefarah `yq` v4 — required for gates (python-yq is rejected)
- `pytest`, `ruff` — required when `src/` exists (missing tools FAIL the
  implement gate unless `HARNESS_ALLOW_MISSING_TOOLS=1`)
- `behave` (or any Gherkin runner) — for `harness/tests/features/*.feature`

Install with `winget install MikeFarah.yq jqlang.jq` (Windows),
`brew install yq jq` (macOS). Python tools via `pip install behave pytest ruff`.

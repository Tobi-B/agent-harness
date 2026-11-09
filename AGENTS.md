# Agent Instructions (portable)

This repo uses the **lean harness** workflow. The contract lives in
`harness/workflow.yaml`. This file is the portable summary that any agent
(opencode, Aider, Cursor, Copilot, Continue, …) can read without tool-specific
setup. Claude Code and opencode also have a `/harness` command.

## Quick Start

1. Read `harness/status.yaml` — `current_phase`, `current_iteration`, autopilot.
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

Per phase: **interview → draft → render → user approves in chat → you record it → run gate → user advances.**

User approval is required for: phase transitions, every ADR, every iteration
design, material changes to already-approved artifacts, exceptions to hardcaps.

## Approval is the user's word, not yours

An artifact is approved when it carries an `approved_by:` marker: a frontmatter
field in markdown artifacts, a `# approved_by: user` comment line in `.feature`
files. There is no hash and no registry — deliberately (see
`harness/docs/adrs/meta-0004-trusted-approval-markers.md`). You physically CAN
write that marker any time, which is exactly why the rule matters: write
`approved_by: user` **only after the user has explicitly approved that artifact
in conversation**. Never pre-fill it in drafts, never infer approval from
silence, and if you materially edit an approved artifact afterwards, tell the
user, ask again, and only then refresh the marker. A fabricated approval defeats
the harness at its core; nothing else in this file matters more than this.

The single exception is `approved_by: autopilot`, and only while the user has
enabled auto mode (see below).

Only those two values count. The gates treat anything else — an empty field,
`""`, `TBD`, `pending`, a leftover template comment — as a **draft**. Leave the
field empty in drafts; do not invent placeholder values.

## Auto mode — only if the user asked for it

Two modes exist. **Without auto** this is a human-in-the-loop development
cycle: the user approves every artifact and every transition. **With auto**
there is no human in the loop: you run every phase except `release` alone.

Enabling is the user's decision, made in conversation. When — and only when —
the user explicitly asks for auto mode, run
`bash harness/gates/autopilot.sh on [--expires 8h] [--max-iterations 3]` for
them. Never enable it on your own initiative, and never edit the `autopilot`
block in `status.yaml` directly.

Check with `bash harness/gates/autopilot.sh status` (exit 0 = on). While it is
on, for every phase except `release`:

- you may mark artifacts you drafted as `approved_by: autopilot` — never
  `approved_by: user`, so it stays honest about what no human read;
- `bash harness/gates/advance.sh <phase>` proceeds without the prompt;
  iteration-cycle phases spend the iteration budget.

Auto mode changes who approves, not what is checked: gates still have to pass,
and you still render designs and leave them for the user to find. If it is off,
expired, or out of budget, stop and say so — do not reach for `--yes`.
`release` always waits for the user, so even a fully auto run ends in front of
a person.

## Gates are executable and pure

Each phase's gate is a runnable script under `harness/gates/`. Run them freely
via `bash harness/gates/<phase>.sh` — they are pure checks with no side effects.
Do not advance if a gate fails.

Phase and iteration transitions happen only via
`bash harness/gates/advance.sh <phase>` (runs the gate, writes
`harness/audit/<phase>-<timestamp>.md`, updates `status.yaml`). It advances the
**current** phase only. The user runs it; you may pass `--yes` only when the
user explicitly told you to advance.

## Project commands

`harness/project.yaml` tells the `implement` gate where the code lives
(`source_dirs`) and how to test, lint and run the acceptance features
(`commands.test`, `commands.lint`, `commands.acceptance`). Commands run from
the project root. Fill it in during `architect`, once the stack is decided,
and confirm the commands with the user. It is project-owned: editing it needs
no meta ADR. An empty command fails the gate — never set one to `true` to make
the gate pass; that is the same kind of lie as a fabricated approval.

## Show designs before asking for approval

In `model` and `design`, render the Mermaid diagrams to a page the user can
look at:

```bash
bash ~/.claude/skills/mermaid-render/render.sh --shared-lib -o <out>.html --title "<title>" <sources>
```

Then show it (`SendUserFile` with `display: "render"`). The `design` gate
requires a rendered HTML that is not older than the markdown, so re-render
after editing. Never ask for design approval without showing the diagram.

## Traceability

Every artifact carries YAML frontmatter with `references:` to what it depends
on (`references: [US-003, ADR-0001]`). The `model` gate verifies that every
diagram's `%% sources:` line references at least one upstream artifact. The
`plan` gate verifies that every approved story is covered by some iteration.

## Acceptance Criteria are Executable

Each user story has a 1:1 Gherkin file under `harness/tests/features/`. The
`implement` gate runs them and requires one per story in the current iteration.
Skeletons live in `harness/templates/`.

## Status

`harness/status.yaml` is the authoritative phase state. Gates never write it;
`advance.sh` and `autopilot.sh` do. Approvals live in the artifacts themselves
as `approved_by:` markers; frontmatter `status:` fields are informational.
`docs/plan.md` frontmatter is the authority on what the iterations are.

## Meta-loop

Changes to the harness itself (`workflow.yaml`, `gates/`, `dor_dod.yaml`,
templates) go through `harness/docs/WORKFLOW_CHANGES.md`: a `meta-NNNN-*.md`
ADR, user approval, version bump. Do not edit `workflow.yaml` ad-hoc.

## Tools

- `bash` >= 4, `jq`, mikefarah `yq` v4 — required for gates (python-yq is rejected)
- whatever the `project.yaml` commands call; a Python project with
  `pyproject.toml` and no configured commands defaults to `pytest`, `ruff`,
  `behave`
- missing tools or unconfigured commands FAIL the implement gate unless
  `HARNESS_ALLOW_MISSING_TOOLS=1`

Install with `winget install MikeFarah.yq jqlang.jq` (Windows, gates run in Git
Bash), `brew install bash yq jq` (macOS). Python tools via
`pip install behave pytest ruff`.

# Agent Instructions (portable)

This repo uses the **lean harness** workflow. The contract lives in
`harness/workflow.yaml`. This file is the portable summary that any agent
(opencode, Aider, Cursor, Copilot, Continue, …) can read without tool-specific
setup. Claude Code and opencode also have a `/harness` command.

## Quick Start

1. Run `bash harness/gates/next.sh` — it prints the phase, the iteration, the
   gate's verdict, the autopilot state, ONE action, and what is waiting for
   the user. It is pure; run it as often as you like.
2. Read `harness/workflow.yaml` — phases, gates, hardcaps — and
   `harness/dor_dod.yaml` — per-phase readiness criteria.
3. Read `harness/docs/plan.md` — the iteration list, once past `plan`.
4. Do what `next.sh` says (see "One tick" below).

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

`design`, `implement`, and `verify` are iteration-scoped: they run once per
iteration in `docs/plan.md` and record their state under
`iterations.<ITER-NN>` in `status.yaml`.

Per phase: **interview → draft → render → user approves in chat → you record it → run gate → advance.**

The user decides, you build. User approval is required for: stories, every
ADR, the plan, every iteration design, the answer to every open decision,
`release`, material changes to already-approved artifacts, exceptions to
hardcaps. Phase transitions are the user's too — unless they switched auto
mode on, which hands you the routine ones (below).

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

`approved_by: autopilot` exists as a second value, and it counts only while the
user has auto mode on **in mode `full`** (below). In the default mode `build`
it is not an approval, and the gates say so.

Only those two values count. The gates treat anything else — an empty field,
`""`, `TBD`, `pending`, a leftover template comment — as a **draft**. Leave the
field empty in drafts; do not invent placeholder values.

## Auto mode — only if the user asked for it

Without auto, every approval and every transition is the user's. Auto mode
hands you a bounded part of that. It has two modes:

| | `build` (default) | `full` (must be named) |
|---|---|---|
| you advance without asking | `design`, `implement`, `verify` | every phase except `release` |
| `approved_by: autopilot` counts | never | while auto is on and unexpired |
| `release` | user | user |

`build` is "the user decides, you build": stories, ADRs, the plan and every
iteration design still need `approved_by: user`; what you carry alone is the
work and the transitions inside an iteration. The user may approve the designs
of several iterations ahead, and the loop then runs that far unattended.
`full` additionally lets you approve what you drafted — as
`approved_by: autopilot`, never `user`, so it stays honest about what no human
read.

Enabling is the user's decision, made in conversation. When — and only when —
the user explicitly asks for it, run
`bash harness/gates/autopilot.sh on [--mode build|full] [--expires 8h] [--max-iterations 3] [--phase-timeout 2h]`
for them. Use `--mode full` only if the user asked for exactly that. Never
enable auto on your own initiative, and never edit the `autopilot` block in
`status.yaml` directly.

Auto mode changes who carries a transition, not what is checked: gates still
have to pass, and you still render every design and show it. Do not work out
for yourself whether auto mode still covers you — ask `next.sh`. When it exits
3, stop and say what is waiting; do not reach for `--yes`. `release` always
waits for the user, so even a fully auto run ends in front of a person.

## Decisions — how you ask instead of guessing

Some questions come up mid-flight and are not yours to answer. Do not decide
them silently and do not bury them in a note: open a decision,
`harness/docs/decisions/DEC-NNN-<slug>.md` (from
`harness/templates/decision.template.md`) — the question, the options, your
recommendation — and leave `approved_by:` empty. While any decision is open,
autopilot carries nothing and `release` does not pass: the machine waits. When
the user answers in chat, record the answer under `## Decision` and write
`approved_by: user`. If the answer changes an artifact the user decided, list
that artifact under the decision's `references:` (`US-003`, `ADR-0002`,
`plan.md`, `project.yaml`) — that is what lets the change past the tripwire.

Open a decision when:

- an artifact the user approved (story, feature file, ADR, plan, design) would
  have to change — including an approved design that no longer fits the code;
- an architectural choice is not covered by an ADR: a new dependency, a schema,
  a public interface, anything security-relevant;
- a story cannot be built as specified;
- a command in `harness/project.yaml` would change, or missing tools would
  have to be allowed;
- a hardcap would be exceeded;
- something is irreversible or leaves the machine (publishing, deleting,
  sending).

Small, reversible choices are yours: make them and record them under
`## Notes` in the iteration file. That an open decision stops the machine is
enforced by the gates; recognising when to open one is on you.

**The tripwire backs this up.** `autopilot.sh on` records the commit it starts
from (decided artifacts must be committed first). While autopilot is on, a
change to something the user decided — the PRD, `plan.md`,
`architecture.md`, a story, a feature file, an ADR, `project.yaml`, or the
harness itself — stops the loop, committed or not, unless an answered
decision references that artifact. Re-enabling autopilot is how the user
accepts a change without one. Approved iteration designs are not on that list:
changing one after approval is a decision too, but only this file says so.

**Coming back:** `bash harness/gates/report.sh` (pure) shows what happened
since autopilot was switched on — transitions and how each happened,
decisions, iteration notes, commits, and what `next.sh` says now.

## One tick

`/harness`, a loop (`/loop /harness`), or any other driver does the same thing:

1. `bash harness/gates/next.sh`.
2. **`action: work`** — do ONE unit of work on what the gate reports missing,
   then commit it. In `implement` one unit is one story, and where your tool
   has subagents, give each story a fresh one: hand it the story, its feature
   file, the approved design and the iteration's `## Notes`; have it add what
   the next story needs to know to `## Notes`. A subagent never writes an
   `approved_by:` marker, never runs `advance.sh` or `autopilot.sh`, and
   reports a question back instead of deciding it — you open the decision.
   If `next.sh` says `unattended: no`, the work is fine with the user in the
   conversation, but a loop stops here.
3. **`action: advance`** — run the command it prints
   (`bash harness/gates/advance.sh <phase>`, no `--yes`), commit, tick again.
4. **`action: approve`** (mode `full` only) — mark what you drafted
   `approved_by: autopilot`, tick again.
5. **`action: await_human`** (exit 3) — show the user exactly what is waiting
   (the rendered design, the decision file, the transition), then stop. A loop
   ends here until they answer.
6. **`action: done`** (exit 4) — the release has passed. Stop.

In the iteration file, everything above `## Verification` is the approved
design; `## Verification` and `## Notes` are yours to fill.

## Gates are executable and pure

Each phase's gate is a runnable script under `harness/gates/`. Run them freely
via `bash harness/gates/<phase>.sh` — they are pure checks with no side effects.
Exit codes: `0` pass, `1` work is missing, `3` only the user's word is missing
(approvals are checked last, after everything structural), `2` the environment
is broken. Do not advance if a gate does not pass.

Phase and iteration transitions happen only via
`bash harness/gates/advance.sh <phase>` (runs the gate, writes
`harness/audit/<phase>-<timestamp>.md`, updates `status.yaml`). It advances the
**current** phase only. The user runs it, or you do where auto mode carries the
phase; pass `--yes` only when the user explicitly told you to advance that
phase. The audit entry records how each transition happened (`interactive`,
`--yes`, or `autopilot(<mode>)`).

## Project commands

`harness/project.yaml` tells the gates where the code lives (`source_dirs`)
and how to test, lint and run the acceptance features (`commands.test`,
`commands.lint`, `commands.acceptance`). Commands run from the project root.
`implement`, `verify` and `release` all run them — a gate re-runs the suite
every time it is asked, so the checkboxes in `## Verification` and the PRD are
your account, never the evidence.

Every command sees `HARNESS_DUE_STORIES` and `HARNESS_DUE_FEATURES`: the
stories of every iteration up to the current one and their feature files
(relative to the project root; at `release`, all of them). Point the
acceptance runner at `$HARNESS_DUE_FEATURES`, or ITER-01 fails on the
undefined steps of later stories.

Fill it in during `architect`, once the stack is decided, and confirm the
commands with the user. It is project-owned: editing it needs no meta ADR, but
under autopilot a change trips the wire (above). An empty command fails the
gate — never set one to `true` to make the gate pass; that is the same kind of
lie as a fabricated approval. `allow_missing_tools: true` (docs-only repos) is
the user's call; `HARNESS_ALLOW_MISSING_TOOLS=1` works only at a terminal and
is ignored while autopilot carries the phase.

## Show designs before asking for approval

In `model` and `design`, render the Mermaid diagrams to a page the user can
look at:

```bash
bash ~/.claude/skills/mermaid-render/render.sh --shared-lib -o <out>.html --title "<title>" <sources>
```

Then show it (`SendUserFile` with `display: "render"`). Until a design is
approved, the `design` gate requires a rendered HTML that is not older than
the markdown, so re-render after editing. Never ask for design approval
without showing the diagram.

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
`advance.sh` and `autopilot.sh` do, and nobody edits it by hand. Approvals live
in the artifacts themselves
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
- missing tools or unconfigured commands FAIL the implement, verify and
  release gates unless `allow_missing_tools: true` in `project.yaml` (or
  `HARNESS_ALLOW_MISSING_TOOLS=1` at a terminal, not under autopilot)
- `git` for the tripwire and the report's commit list

Install with `winget install MikeFarah.yq jqlang.jq` (Windows, gates run in Git
Bash), `brew install bash yq jq` (macOS). Python tools via
`pip install behave pytest ruff`.

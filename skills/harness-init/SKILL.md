---
name: "harness-init"
description: |
  Scaffold the lean development harness into a project: a phase machine
  (discover → architect → model → plan → ⟳design/implement/verify → release)
  with executable gates, lightweight user approval ("approved by user" markers
  in the artifacts, no hashes), per-iteration design
  reviews rendered as Mermaid diagrams, and a git-persisted state file. Use when
  the user wants to start a project in a structured way, or asks for a "harness",
  "dev loop", "development process", "project scaffold", "spec-driven
  development", user stories with Gherkin criteria, ADRs, a PRD, or an agent
  workflow with human approval gates — even if they never say "harness".
---

# Harness Init

Installs the harness and starts its git-based state loop. After install, all
day-to-day work runs through `/harness`.

## What makes this harness different

Gates are **executable and pure** (bash + exit codes, no side effects), and
approval is **the user's word in chat**: when the user approves an artifact,
the agent writes a plain `approved_by: user` marker into it (frontmatter in
`.md`, a `# approved_by: user` comment in `.feature` files) — no hashes, no
registry, no script for the user to run. The gates only check that the marker
exists; writing it *before* the user actually approved defeats the harness at
its core. Never do that, and re-ask before keeping the marker on an artifact
you materially changed after approval.

## Install

1. **Determine the target directory.** Ask if unclear. Installing into an
   existing codebase is fine — nothing outside `harness/`, `.claude/commands/`,
   `.opencode/command/`, and `AGENTS.md` is touched, and an existing `AGENTS.md`
   is preserved (the harness copy lands as `AGENTS.harness.md` to merge).

2. **Run the installer** from this skill's bundled copy:

   ```bash
   bash ~/.claude/skills/harness-init/assets/harness/init.sh <TARGET_DIR> --name <PROJECT_NAME>
   ```

   Flags: `--no-git` to skip git init/commit, `--force` to replace an existing
   `harness/`. The script refuses to overwrite an existing harness otherwise.

3. **Check the tools.** Gates need `bash`, `jq`, and mikefarah `yq` v4:

   ```bash
   winget install MikeFarah.yq jqlang.jq    # Windows
   brew install yq jq                        # macOS
   ```

   macOS also needs `brew install bash` — its `/bin/bash` is 3.2 and the gates
   need 4+. On Windows, run the gates in Git Bash; the installer writes a
   `.gitattributes` that keeps them LF (CRLF checkouts break every gate).

   Verify with `bash <TARGET>/harness/tests/gates/test_gates.sh` — the harness
   self-tests its own gates. If they pass, the install is sound.

4. **Project commands.** `harness/project.yaml` holds the test, lint and
   acceptance commands the `implement` gate runs from the project root, plus
   `source_dirs`. For a Python project with `pyproject.toml` it can stay empty
   (pytest / ruff / behave). For anything else — C++/JUCE, TypeScript, … — it
   must be filled in, or `implement` fails. If the stack is already known, fill
   it in now with the user; otherwise it is done in `architect`.

5. **Hand off.** Tell the user the harness is ready and that `/harness` starts the
   `discover` phase. If they already described their project in this
   conversation, offer to begin the interview right away rather than making
   them repeat themselves.

## After install

The loop, and who does what:

| Step | Who |
|---|---|
| Interview, draft artifacts, render diagrams | agent |
| `bash harness/gates/<phase>.sh` (pure check) | agent, freely |
| Approve an artifact ("approved" in chat) | **user** — then the agent records `approved_by: user` in the file |
| `bash harness/gates/next.sh` (pure: what now, whose move) | agent, at the start of every tick |
| `bash harness/gates/report.sh` (pure: what happened since autopilot went on) | anyone, anytime |
| `bash harness/gates/advance.sh <phase>` | **user** (agent only with `--yes` on explicit instruction, or where auto mode carries the phase) |
| Answer an open decision (`docs/decisions/DEC-*.md`) | **user** — then the agent records the answer and `approved_by: user` |
| `bash harness/gates/autopilot.sh on\|off\|status` | **user decision** — agent runs `on` only on explicit chat instruction |

Phases: `discover → architect → model → plan → ⟳(design → implement → verify) → release`.
The middle three are iteration-scoped and repeat per iteration in
`harness/docs/plan.md`.

## Auto mode and the loop

Without auto, the user approves every artifact and every phase transition.
Auto mode hands the agent a bounded part of that, in one of two modes:

- **`build`** (default) — *the user decides, the agent builds.* The agent
  carries the work and the transitions of `design`, `implement`, `verify` and
  approves nothing: stories, ADRs, the plan and every iteration design still
  need `approved_by: user`. Designs may be approved several iterations ahead.
- **`full`** (must be named) — the agent also approves what it drafted, as
  `approved_by: autopilot`, in every phase except `release`.

Enabling is the user's call, made in chat: when they explicitly ask for auto
mode, run `bash harness/gates/autopilot.sh on --expires 8h --max-iterations 3`
for them (add `--mode full` only if they asked for exactly that) — never on
your own initiative. `release` always waits for the user.

`bash harness/gates/next.sh` answers "what now?" with one action and an exit
code (0 go on, 3 the user's move, 4 done). `/harness` is one tick of that, so
Claude Code's built-in `/loop /harness` runs the project until something
waits for the user: an unapproved design, an open decision
(`harness/docs/decisions/DEC-NNN-*.md`), a transition that is theirs, or the
release. While autopilot runs, a change to anything the user decided (PRD,
plan, stories, features, ADRs, `project.yaml`) stops it unless an answered
decision covers it; `bash harness/gates/report.sh` shows what happened. The
`implement`, `verify` and `release` gates run the project's own commands, so
fill in `harness/project.yaml` once the stack is decided — and point the
acceptance runner at `$HARNESS_DUE_FEATURES`. The rules are in the project's
`AGENTS.md`.

## Notes

- Keep the scaffold lean — do not add documents or restructure it during
  install. The harness's value is that a human can hold the whole thing in
  their head.
- Only `approved_by: user` counts — plus `approved_by: autopilot` while auto
  mode is on in mode `full`; the gates treat every other value as a draft.
- Never fabricate approvals: `approved_by: user` goes into a file only after
  the user explicitly approved that artifact in conversation. Nothing verifies
  this mechanically — which is exactly why it must hold.
- In `design`, render the Mermaid with the `mermaid-render` skill and show the
  user the page before asking for approval. A design gate that was approved
  without anyone looking at the diagram defeats the purpose.
- If the user asks how the loop works, read `harness/workflow.yaml` and
  summarize it rather than inventing a different process.

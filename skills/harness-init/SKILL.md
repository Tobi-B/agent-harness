---
name: harness-init
description: |
  Scaffold the lean development harness into a project: a phase machine
  (discover → architect → model → plan → ⟳design/implement/verify → release)
  with executable gates, hash-verified user sign-off, per-iteration design
  reviews rendered as Mermaid diagrams, and a git-persisted state file. Use when
  the user wants to start a project in a structured way, or asks for a "harness",
  "dev loop", "development process", "project scaffold", "spec-driven
  development", user stories with Gherkin criteria, ADRs, a PRD, or an agent
  workflow with human approval gates — even if they never say "harness".
---

# Harness Init

Installs the harness and starts its git-based state loop. After install, all
day-to-day work runs through `/loop`.

## What makes this harness different

Gates are **executable and pure** (bash + exit codes, no side effects), and
approvals are **not forgeable by the agent**: sign-off is a sha256 registry in
`harness/status.yaml` written only by the user running `signoff.sh`. Editing a
signed-off artifact invalidates its sign-off. Do not try to work around this —
it is the point.

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

   Verify with `bash <TARGET>/harness/tests/gates/test_gates.sh` — the harness
   self-tests its own gates. If they pass, the install is sound.

4. **Hand off.** Tell the user the harness is ready and that `/loop` starts the
   `discover` phase. If they already described their project in this
   conversation, offer to begin the interview right away rather than making
   them repeat themselves.

## After install

The loop, and who does what:

| Step | Who |
|---|---|
| Interview, draft artifacts, render diagrams | agent |
| `bash harness/gates/<phase>.sh` (pure check) | agent, freely |
| `bash harness/gates/signoff.sh <artifact>` | **user only** |
| `bash harness/gates/advance.sh <phase>` | **user** (agent only with `--yes` on explicit instruction) |

Phases: `discover → architect → model → plan → ⟳(design → implement → verify) → release`.
The middle three are iteration-scoped and repeat per iteration in
`harness/docs/plan.md`.

## Notes

- Keep the scaffold lean — do not add documents or restructure it during
  install. The harness's value is that a human can hold the whole thing in
  their head.
- Never fabricate approvals or pre-fill `signed_off_artifacts`. A forged entry
  fails the gate, because the hash will not match.
- In `design`, render the Mermaid with the `mermaid-render` skill and show the
  user the page before asking for approval. A design gate that was approved
  without anyone looking at the diagram defeats the purpose.
- If the user asks how the loop works, read `harness/workflow.yaml` and
  summarize it rather than inventing a different process.

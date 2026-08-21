---
name: harness-init
description: |
  Scaffold the lean development harness into a project: a phase machine
  (discover → architect → model → plan → ⟳design/implement/verify → release)
  with executable gates, lightweight user approval ("approved_by: user" markers
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

Gates are **executable and pure** (bash + exit codes, no side effects): you may
run them as often as you like, and no amount of arguing makes a failing one pass.

Approval works the other way round — on trust, not on mechanism. An artifact is
approved when it carries an `approved_by: user` marker (frontmatter in markdown,
a `# approved_by: user` comment in `.feature` files). There is no hash and no
registry; an earlier sha256 scheme was removed in
`harness/docs/adrs/meta-0004-trusted-approval-markers.md`. You physically *can*
write that marker at any moment, which is exactly why the rule is absolute:
write it **only after the user has explicitly approved that artifact in
conversation**. Never pre-fill it in a draft, never read approval into silence,
and after a material edit to an approved artifact, ask again before restoring
the marker.

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

4. **Hand off.** Tell the user the harness is ready and that `/harness` starts the
   `discover` phase. If they already described their project in this
   conversation, offer to begin the interview right away rather than making
   them repeat themselves.

## After install

The loop, and who does what:

| Step | Who |
|---|---|
| Interview, draft artifacts, render diagrams | agent |
| `bash harness/gates/<phase>.sh` (pure check) | agent, freely |
| Approving an artifact | **user**, in conversation |
| Writing the `approved_by:` marker | agent — *only after* the user approved |
| `bash harness/gates/advance.sh <phase>` | **user** (agent only with `--yes` on explicit instruction, or under auto mode) |
| `bash harness/gates/autopilot.sh on\|off\|status` | agent, but **only** on the user's explicit chat instruction |

Phases: `discover → architect → model → plan → ⟳(design → implement → verify) → release`.
The middle three are iteration-scoped and repeat per iteration in
`harness/docs/plan.md`.

## Auto mode

Two modes exist. **Without auto**, this is a human-in-the-loop cycle: the user
approves every artifact and every transition. **With auto**, there is no human
in the loop — the agent runs every phase except `release`, which always waits
for a person, so even a fully unattended run ends in front of one.

If the user wants unattended runs, tell them about
`bash harness/gates/autopilot.sh on --expires 8h --max-iterations 3`. Enabling
is the user's decision, made in conversation: run it **only** when they
explicitly ask, never on your own initiative, and never edit the `autopilot`
block in `status.yaml` by hand. It is bounded by wall-clock expiry *and* an
iteration budget — the emergency brake for a forgotten auto run — and machine
approvals are marked `approved_by: autopilot`, never `user`, so it stays
visible what no human read. See
`harness/docs/adrs/meta-0005-full-autopilot-except-release.md`.

Auto mode changes who approves, not what is checked: gates still have to pass,
and designs still get rendered for the user to find afterwards. It pairs
naturally with Claude Code's built-in `/loop`, which supplies the heartbeat
while the gates supply the guardrails.

## Notes

- Keep the scaffold lean — do not add documents or restructure it during
  install. The harness's value is that a human can hold the whole thing in
  their head.
- Never fabricate an approval. Nothing mechanical stops you from writing
  `approved_by: user` into an artifact nobody read — the gate cannot tell the
  difference. That is precisely why it must never happen.
- In `design`, render the Mermaid with the `mermaid-render` skill and show the
  user the page before asking for approval. A design gate that was approved
  without anyone looking at the diagram defeats the purpose.
- If the user asks how the loop works, read `harness/workflow.yaml` and
  summarize it rather than inventing a different process.

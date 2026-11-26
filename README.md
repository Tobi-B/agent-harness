# agent-harness

**A phase machine for coding agents: the agent builds, you decide, and bash
scripts — not prompts — check that both happened.**

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

Every phase ends in a gate: a pure bash script that exits `0` (pass), `1` (work
missing), `3` (only your approval missing) or `2` (environment broken). The
agent can run gates as often as it likes; it cannot talk a failing one into
passing.

## Core ideas

1. **Gates are executable and pure.** Every check in
   [`workflow.yaml`](harness/workflow.yaml) is enforced by a script. Only
   `advance.sh` changes state — it runs the gate, writes an audit entry, and
   refuses to move past a failure.
2. **Approval is your word.** You say "approved" in chat; only then does the
   agent write `approved_by: user` into the artifact. No hash, no registry — so
   the rule is absolute. ([meta-0004](harness/docs/adrs/meta-0004-trusted-approval-markers.md))
3. **Evidence, not checkboxes.** `implement`, `verify` and `release` run the
   project's own test, lint and acceptance commands every time.
   ([meta-0009](harness/docs/adrs/meta-0009-evidence-not-checkboxes.md))
4. **Ask, don't guess.** A question that isn't the agent's to answer becomes
   `docs/decisions/DEC-NNN-*.md`; while it is open, the machine stops.
   ([meta-0008](harness/docs/adrs/meta-0008-decision-gated-autonomy.md))

## What each phase produces

| Phase | Output |
|---|---|
| discover | PRD, user stories, one Gherkin `.feature` per story |
| architect | ≤ 3 ADRs, `architecture.md`, real commands in `project.yaml` |
| model | C4, sequence and state diagrams (Mermaid, traced to sources) |
| plan | `plan.md` — stories sliced into iterations `ITER-NN` |
| design | per iteration: a diagrammed design, **rendered and shown** before approval |
| implement | TDD per story, one fresh subagent each |
| verify | `## Verification` in the iteration file; commands re-run |
| release | `verify-report.md` against the PRD's success criteria and NFRs |

## How to use it

Type **`/harness`** (Claude Code, opencode) — or point any agent at
[`AGENTS.md`](AGENTS.md). Each tick asks `bash harness/gates/next.sh` what now
and does exactly one thing:

| `action` | The agent… |
|---|---|
| `work` | does one unit of work, commits |
| `advance` | runs `advance.sh <phase>` |
| `await_human` | shows you what is waiting, and **stops** |
| `done` | release passed — stops |

A phase runs: interview → draft → render → **you approve** → marker → gate →
advance. `/loop /harness` repeats ticks until something waits for you.

**Auto mode** — only if you ask: `bash harness/gates/autopilot.sh on --expires 8h`

| | `build` (default) | `full` (must be named) |
|---|---|---|
| agent advances alone | design, implement, verify | every phase but release |
| agent may approve | nothing | its own drafts, as `approved_by: autopilot` |
| release | you | you |

While it runs, a change to anything you decided (PRD, plan, stories, ADRs,
`project.yaml`) trips a wire and stops it. `bash harness/gates/report.sh` shows
what happened while you were away.

## Install

```bash
bash harness/init.sh <TARGET_DIR> --name <PROJECT_NAME>   # scaffold into a project
#   --target claude|opencode|all  (default all): which agent gets the /harness command
bash tools/install-skills.sh                               # skills → ~/.claude/skills (OpenCode reads it too)
bash tools/install-skills.sh --target opencode             # skills → ~/.config/opencode/skills
bash tools/install-skills.sh --target all                  # both
```

Adds `harness/`, the `/harness` command, `AGENTS.md` (an existing one is kept;
the copy lands as `AGENTS.harness.md`), and one git commit unless `--no-git`.

Requires `bash` ≥ 4 and `git`. Everything else the gates use — mikefarah
`yq` v4, `jq`, the Mermaid library — is pinned per project and fetched into
`harness/deps/` (git-ignored, each file checked against its SHA-256); nothing
is installed system-wide, and a system-wide copy does not count:

```bash
bash harness/deps/setup.sh   # in the project, once per machine — about 20 MB
```

Plus whatever your `project.yaml` commands call (Python with `pyproject.toml`
falls back to `pytest`, `ruff`, `behave`). On Windows run the gates in Git
Bash; macOS needs `brew install bash`.

## This repo

| Path | |
|---|---|
| [`harness/`](harness/) | the harness — start at [`harness/README.md`](harness/README.md) |
| [`skills/harness-init/`](skills/harness-init/) | skill that scaffolds it (bundled copy of `harness/`) |
| [`skills/mermaid-render/`](skills/mermaid-render/) | skill that makes Mermaid diagrams reviewable |
| [`AGENTS.md`](AGENTS.md) | portable agent contract |
| [`tools/`](tools/) | install, package, sync and repo checks |

The repo is its own harness installation (`harness/status.yaml`).

**Developing:** `bash harness/tests/gates/test_gates.sh` self-tests the gates;
CI adds shellcheck, a clean scaffold, drift and `tools/check-repo.sh`. Work on a
branch, one worktree per parallel session. Changes to the harness itself need a
`meta-NNNN` ADR, approval and a version bump — see
[`WORKFLOW_CHANGES.md`](harness/docs/WORKFLOW_CHANGES.md).

## License

Public domain — [The Unlicense](LICENSE).

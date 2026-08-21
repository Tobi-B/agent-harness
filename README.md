# agent-harness

A documentation-driven development workflow for coding agents, with **executable
gates** and **human approval** where it matters.

Most agent workflows are a prompt that says "please follow these steps". This one
is a phase machine whose every rule is a bash script that exits 0 or 1. The agent
can run the checks freely; it cannot make a failing gate pass by being persuasive.

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

Each phase produces specific artifacts, and each has a gate script that checks
them. `design`, `implement`, and `verify` are iteration-scoped — they run once per
iteration in the plan, then loop.

## What's in this repo

| Path | What it is |
|---|---|
| [`harness/`](harness/) | The harness itself — phases, gates, templates, docs. **Start here:** [`harness/README.md`](harness/README.md) |
| [`skills/harness-init/`](skills/harness-init/) | Claude Code skill that scaffolds the harness into any project (carries its own copy of `harness/`) |
| [`skills/mermaid-render/`](skills/mermaid-render/) | Claude Code skill that renders Mermaid diagrams into a reviewable HTML page |
| [`AGENTS.md`](AGENTS.md) | Portable agent contract — readable by any agent, no tool-specific setup |
| [`tools/`](tools/) | `install-skills.sh`, `sync-skill.sh` (keeps the skill's bundled copy in sync) |

This repo *is* a harness installation as well as its source, so
`harness/status.yaml` tracks its own phase state.

## Two ideas it's built on

**Gates are pure and executable.** Every criterion listed under a phase's
`checks:` in [`harness/workflow.yaml`](harness/workflow.yaml) is enforced by the
referenced script — nothing is declared but unchecked. Gates never mutate state;
only `gates/advance.sh` does, and it runs the gate first, writes an audit entry,
and refuses to move past a failure.

**Approval is the user's word, not the agent's.** When you approve an artifact in
conversation, the agent writes a plain `approved_by: user` marker into that
artifact. There is no hash and no registry — deliberately. The agent *can*
physically write that marker at any time, which is exactly why the rule is stated
so bluntly in `AGENTS.md`: write it only after a human actually approved. See
[`meta-0004`](harness/docs/adrs/meta-0004-trusted-approval-markers.md) for why the
earlier hash-based scheme was removed.

Auto mode exists for unattended runs — the agent then marks artifacts
`approved_by: autopilot`, never `user`, so it stays visible what no human read.
It is bounded by wall-clock expiry and an iteration budget, and `release` always
waits for a person.

## Install into your project

```bash
bash harness/init.sh <TARGET_DIR> --name <PROJECT_NAME>
```

Nothing outside `harness/`, `.claude/commands/`, `.opencode/command/`, and
`AGENTS.md` is touched; an existing `AGENTS.md` is preserved. Then work one phase
at a time — via `/harness` in Claude Code or opencode, or by pointing any other
agent at `AGENTS.md`.

Install the skills for your own account with:

```bash
bash tools/install-skills.sh
```

## Requirements

- `bash`, `jq`, and mikefarah `yq` **v4** (the gate library rejects python-yq)
- `pytest`, `ruff` — once the project has a `src/`
- `behave`, or any Gherkin runner, for `tests/features/*.feature`

```bash
winget install MikeFarah.yq jqlang.jq   # Windows
brew install yq jq                      # macOS
pip install behave pytest ruff
```

## Development

```bash
bash harness/tests/gates/test_gates.sh
```

The harness self-tests its own gates. CI additionally runs shellcheck, scaffolds
into a clean directory to confirm a fresh install starts with zero approvals, and
checks that the skill's bundled copy has not drifted from `harness/`.

Changes to the harness itself go through the meta-loop documented in
[`harness/docs/WORKFLOW_CHANGES.md`](harness/docs/WORKFLOW_CHANGES.md): a
`meta-NNNN` ADR, approval, and a version bump in `workflow.yaml`.

## License

Public domain — [The Unlicense](LICENSE). Do whatever you want with it.

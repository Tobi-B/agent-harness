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
| [`skills/mermaid-render/`](skills/mermaid-render/) | Claude Code skill that makes Mermaid diagrams reviewable: a published Artifact by default, `render.sh` for a local HTML file (which the `design` gate needs) |
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

Besides `harness/`, the installer adds the `/harness` command for Claude Code
and opencode, `AGENTS.md`, a `.shellcheckrc`, and LF rules in `.gitattributes`.
Unless you pass `--no-git` it also adds one `.gitignore` entry, initialises a
repo if there is none, and makes one commit. An existing `AGENTS.md` is kept —
the harness copy lands next to it as `AGENTS.harness.md`. Then work one phase at
a time — via `/harness` in Claude Code or opencode, or by pointing any other
agent at `AGENTS.md`.

Install the skills for your own account with:

```bash
bash tools/install-skills.sh           # copy this repo's skills to ~/.claude/skills
bash tools/install-skills.sh --check   # is the installed copy still this repo's?
bash tools/package-skill.sh            # zips for uploading as account skills
```

This repo is the only place the skills are edited. The installed copy and the
account skills are built from it, each stamped with the workflow version and
commit it came from.

## Requirements

- `bash` **>= 4**, `jq`, and mikefarah `yq` **v4** (the gate library rejects python-yq)
- whatever the commands in `harness/project.yaml` call: the `implement` gate
  runs your stack's test, lint and acceptance commands from there. A Python
  project with a `pyproject.toml` and no configured commands falls back to
  `pytest`, `ruff` and `behave`.

```bash
winget install MikeFarah.yq jqlang.jq   # Windows — run the gates in Git Bash
brew install bash yq jq                 # macOS — its /bin/bash is 3.2
pip install behave pytest ruff          # only for the Python fallback
```

## Development

```bash
bash harness/tests/gates/test_gates.sh
```

The harness self-tests its own gates. CI additionally runs shellcheck, scaffolds
into a clean directory to confirm a fresh install starts with zero approvals,
checks that the skill's bundled copy has not drifted from `harness/`, and runs
`tools/check-repo.sh`: no removed concept is still being taught, the installed
`/harness` commands match their sources in `harness/glue/`, and the workflow
version that is live has an approved ADR behind it.

Work on a branch and merge through a pull request with CI green. Run parallel
agent sessions in separate worktrees, not in one checkout — two sessions
sharing a working tree is how unrelated changes ended up in each other's
commits here.

Changes to the harness itself go through the meta-loop documented in
[`harness/docs/WORKFLOW_CHANGES.md`](harness/docs/WORKFLOW_CHANGES.md): a
`meta-NNNN` ADR, approval, and a version bump in `workflow.yaml`.

## License

Public domain — [The Unlicense](LICENSE). Do whatever you want with it.

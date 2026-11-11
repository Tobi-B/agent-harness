# Lean Harness

Documentation-driven agent workflow with executable gates. The agent interviews,
drafts, renders, asks for approval, and only then advances. Architecture and
per-iteration designs require explicit user approval (human-in-the-loop).

**Trust model**: gates are pure checks the agent may run freely; approval is the
user's word. When the user approves an artifact in conversation, the agent
records a plain `approved_by: user` marker in the artifact itself — no hashes,
no registry. The gates check that the marker exists; honesty about *when* to
write it is the agent's obligation, not a mechanism.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

`design`, `implement`, and `verify` are **iteration-scoped**: they run once per
iteration listed in `docs/plan.md`. `advance.sh verify` either loops back to
`design` for the next iteration or moves on to `release`.

| Phase | Produces | Approved |
|---|---|---|
| `discover` | stories + 1:1 Gherkin features | each story **and** feature |
| `architect` | ADRs (max 3) + `architecture.md` | each ADR |
| `model` | system-level C4 / sequence / state diagrams | — |
| `plan` | `docs/plan.md` with the iteration list | the plan |
| `design` | `docs/iterations/ITER-NN.md` + rendered `.html` | each iteration design |
| `implement` | code in the project's `source_dirs`, tests | — |
| `verify` | `## Verification` in the iteration file | — |
| `release` | `docs/verify-report.md` | — |

## How to run

1. Fill `docs/prd.md` (Goals, Success Criteria, NFRs — the gate checks them).
2. Run `/harness` and work one phase at a time.
3. Approve artifacts in conversation ("approved") — the agent then writes
   `approved_by: user` into the artifact's frontmatter (or as a
   `# approved_by: user` comment in `.feature` files).
4. Check any phase anytime: `bash gates/<phase>.sh` (pure, CI-safe).
5. Advance: `bash gates/advance.sh <phase>` — runs the gate, writes the audit,
   updates `status.yaml`, moves to the next phase or iteration.
6. Lost? `bash gates/next.sh` says where you stand and whose move it is.

## Auto mode (optional)

**Without auto** every artifact approval and every phase transition is yours.
**With auto** you hand the agent a bounded part of that. Say so in chat; the
agent then runs:

```bash
bash gates/autopilot.sh on --expires 8h --max-iterations 3     # mode build
bash gates/autopilot.sh on --mode full --expires 8h            # must be named
bash gates/autopilot.sh status     # exit 0 = on and unexpired
bash gates/autopilot.sh off
```

| | `build` (default) | `full` |
|---|---|---|
| agent advances alone | `design`, `implement`, `verify` | every phase except `release` |
| `approved_by: autopilot` counts | never | while auto is on and unexpired |
| `release` | you | you |

`build` is *you decide, the agent builds*: stories, ADRs, the plan and every
iteration design need your approval — the design gate enforces it — and the
grind inside an iteration runs alone. Approve the designs of the next N
iterations in one sitting and the loop runs N iterations unattended. `full` is
the v6 behaviour: the agent also approves what it drafted, visibly, as
`approved_by: autopilot`.

Auto mode expires on wall clock and iteration count, and optionally on a stall
(`--phase-timeout 2h`: a phase whose gate stays red that long becomes your
move). Gates still have to pass. See
`docs/adrs/meta-0008-decision-gated-autonomy.md`.

## Decisions

When the agent hits a question it may not answer alone — an approved artifact
would have to change, an architectural choice no ADR covers, a story that
cannot be built as written — it writes `docs/decisions/DEC-NNN-<slug>.md`
(question, options, recommendation) and leaves `approved_by:` empty. While a
decision is open, autopilot carries nothing and `release` does not pass. You
answer in chat; the agent records the answer and the marker.

## What now?

```bash
bash gates/next.sh
```

Pure. Prints phase, iteration, the gate's verdict, the autopilot state, one
action (`work`, `advance`, `approve`, `await_human`, `done`) and what is
waiting for you. Exit `0` = the agent may go on, `3` = your move, `4` = done,
`2` = environment broken — so a loop is `while bash gates/next.sh; do <one
tick>; done`, and `/loop /harness` in Claude Code is exactly that.

## Install into another project

```bash
bash harness/init.sh <TARGET_DIR> --name <PROJECT>
```

Copies the machinery, resets all state, and makes the initial commit. Also
available as the `harness-init` skill, which carries its own copy of the
harness — see `tools/sync-skill.sh` in the source repo.

## Files

| Path | Purpose |
|---|---|
| `workflow.yaml` | Phases, `scope`, gates (`run:` + enforced `checks:`), hardcaps. |
| `dor_dod.yaml` | Definition of Ready / Done per phase; `(manual)` = not machine-checked. |
| `status.yaml` | Live state: phase, current iteration, per-iteration gate flags, autopilot budget. |
| `project.yaml` | **Project-owned**: source dirs + test/lint/acceptance commands for the implement gate. Editing it is normal project work, no meta ADR. |
| `docs/prd.md` | Goals, Non-Goals, Success Criteria, NFRs. |
| `docs/architecture.md` | C4 architecture + cross-cutting concerns. |
| `docs/plan.md` | **Iteration list in frontmatter** — the source of truth for the cycle. |
| `docs/iterations/` | Per-iteration design + verification, plus the rendered review page. |
| `docs/adrs/` | MADR ADRs. `meta-*.md` = workflow ADRs, exempt from the 3-ADR cap. |
| `templates/` | Feature and iteration skeletons (outside `tests/` so behave ignores them). |
| `glue/` | Canonical copies of the `/harness` command (Claude Code + opencode) and `.shellcheckrc`; `init.sh` installs them to their hidden target paths. |
| `docs/decisions/` | `DEC-NNN-*.md` — questions the agent may not answer alone. Open until `approved_by: user`. |
| `gates/<phase>.sh` | Pure phase checks — no state mutation. Exit 0 pass, 1 work missing, 3 only your approval missing, 2 environment. |
| `gates/next.sh` | Pure: "what now?" — one action and whose move it is. The question a loop asks every tick. |
| `gates/advance.sh` | Gate + audit + status update + phase/iteration transition. Yours, or the agent's where auto mode carries the phase. |
| `gates/autopilot.sh` | Auto mode on/off — run only on the user's explicit instruction; modes `build`/`full`, bounded by expiry + budget. |
| `init.sh` | Install the harness into another project. |
| `tests/gates/test_gates.sh` | Self-tests for the gates themselves. |
| `audit/*.md` | Phase audit trail, written by `advance.sh`. |

## Gate strictness

- Every criterion under `gate.checks:` in `workflow.yaml` is enforced by the
  script — nothing declared-but-unchecked.
- Each gate requires its predecessor's `gate_passed` flag.
- `plan` requires **every** approved story to be covered by some iteration.
- `design` requires a rendered HTML that is not older than the markdown until
  the design is approved — you cannot approve a design nobody could look at,
  or an obviously stale one.
- `implement` runs the commands from `project.yaml` in the **project root** (the
  directory containing `harness/`). No source, an unconfigured command or a
  missing tool **fails** it; `HARNESS_ALLOW_MISSING_TOOLS=1` downgrades those to
  warnings. A command that runs and fails is never downgraded. TODO/FIXME in
  delivered code fails it — comments included.
- `advance.sh` only advances the **current** phase — it cannot rewind or skip.
- Gates check structure first and approvals last, and exit 3 instead of 1
  when only an approval is missing.
- `release` fails while any decision in `docs/decisions/` is open.
- Approval counts only as `approved_by: user`, or as `approved_by: autopilot`
  while auto mode is on in mode `full`;
  empty values and placeholders (`TBD`, `pending`, `""`) are drafts.
- `release` requires every PRD checkbox checked and every iteration verified.

## Rendering diagrams

```bash
bash ~/.claude/skills/mermaid-render/render.sh --shared-lib \
  -o docs/iterations/ITER-01.html --title "ITER-01 Design" docs/iterations/ITER-01.md
```

The `design` gate compares file timestamps: the rendered page must not be older
than its markdown source, so re-render after editing.

`--shared-lib` puts one `mermaid.min.js` next to the iteration pages and keeps
each page at ~7 KB — worth it since these are committed. Drop the flag for a
single self-contained file (~3.5 MB) when sending a review to someone.

## Testing the harness itself

```bash
bash tests/gates/test_gates.sh
shellcheck -x gates/*.sh tests/gates/*.sh
```

Both run in CI, along with a drift check between the repo and the skill assets.

## Meta-loop

Changes to `workflow.yaml`, `gates/`, `dor_dod.yaml`, or templates go through
`docs/WORKFLOW_CHANGES.md`: a `meta-NNNN-*.md` ADR, user approval, version bump.

## Tools required

- `bash` **>= 4**, `jq`, mikefarah `yq` **v4** (the gate library rejects python-yq)
- whatever your `project.yaml` commands call — for a Python project without
  configured commands: `pytest`, `ruff`, `behave`

Install: `winget install MikeFarah.yq jqlang.jq` (Windows, run gates in Git
Bash), `brew install bash yq jq` (macOS — its /bin/bash is 3.2). Python tools via
`pip install behave pytest ruff`.

**Windows:** `init.sh` writes a `.gitattributes` that pins LF for `harness/**`
and `*.feature`. Without it, git's default `core.autocrlf=true` checks the gate
scripts out with CRLF and every gate dies on its first line.

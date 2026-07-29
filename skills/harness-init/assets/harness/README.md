# Lean Harness

Documentation-driven agent workflow with executable gates. The agent interviews,
drafts, renders, asks for approval, and only then advances. Architecture and
per-iteration designs require explicit user sign-off (human-in-the-loop).

**Trust model**: gates are pure checks the agent may run freely; approvals and
phase transitions are user actions the agent cannot forge. Sign-offs are
sha256-hashed — editing a signed-off artifact invalidates its sign-off.

## The loop

```
discover → architect → model → plan → ⟳( design → implement → verify ) → release
```

`design`, `implement`, and `verify` are **iteration-scoped**: they run once per
iteration listed in `docs/plan.md`. `advance.sh verify` either loops back to
`design` for the next iteration or moves on to `release`.

| Phase | Produces | Signed off |
|---|---|---|
| `discover` | stories + 1:1 Gherkin features | each story **and** feature |
| `architect` | ADRs (max 3) + `architecture.md` | each ADR |
| `model` | system-level C4 / sequence / state diagrams | — |
| `plan` | `docs/plan.md` with the iteration list | the plan |
| `design` | `docs/iterations/ITER-NN.md` + rendered `.html` | each iteration design |
| `implement` | `src/**`, `tests/**` | — |
| `verify` | `## Verification` in the iteration file | — |
| `release` | `docs/verify-report.md` | — |

## How to run

1. Fill `docs/prd.md` (Goals, Success Criteria, NFRs — the gate checks them).
2. Run `/harness` and work one phase at a time.
3. Approve artifacts yourself: `bash gates/signoff.sh <path>`.
4. Check any phase anytime: `bash gates/<phase>.sh` (pure, CI-safe).
5. Advance: `bash gates/advance.sh <phase>` — runs the gate, writes the audit,
   updates `status.yaml`, moves to the next phase or iteration.

## Autopilot (optional)

Once the plan is approved, you can let the agent run the routine part alone:

```bash
bash gates/autopilot.sh on --expires 8h --max-iterations 3
bash gates/autopilot.sh status     # exit 0 = on
bash gates/autopilot.sh off
```

It covers `design → implement → verify` only, and expires on both wall clock and
iteration count. `discover`, `architect`, `model`, `plan` and `release` always
stop for you — that is where the irreversible decisions are. Auto-approvals are
recorded as `by: autopilot(<you>), auto: true`, so the registry always shows what
a human actually read. Gates still have to pass; autopilot changes who approves,
not what is checked. See `docs/adrs/meta-0003-bounded-autopilot.md`.

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
| `status.yaml` | Live state: phase, current iteration, per-iteration gate flags, sign-off registry. |
| `docs/prd.md` | Goals, Non-Goals, Success Criteria, NFRs. |
| `docs/architecture.md` | C4 architecture + cross-cutting concerns. |
| `docs/plan.md` | **Iteration list in frontmatter** — the source of truth for the cycle. |
| `docs/iterations/` | Per-iteration design + verification, plus the rendered review page. |
| `docs/adrs/` | MADR ADRs. `meta-*.md` = workflow ADRs, exempt from the 3-ADR cap. |
| `templates/` | Feature and iteration skeletons (outside `tests/` so behave ignores them). |
| `gates/<phase>.sh` | Pure phase checks — no state mutation. |
| `gates/signoff.sh` | **User-run**: records artifact sign-off (sha256) in `status.yaml`. |
| `gates/advance.sh` | **User-run**: gate + audit + status update + phase/iteration transition. |
| `gates/autopilot.sh` | **User-run**: bounded auto-approve for the iteration cycle. |
| `init.sh` | Install the harness into another project. |
| `tests/gates/test_gates.sh` | Self-tests for the gates themselves. |
| `audit/*.md` | Phase audit trail, written by `advance.sh`. |

## Gate strictness

- Every criterion under `gate.checks:` in `workflow.yaml` is enforced by the
  script — nothing declared-but-unchecked.
- Each gate requires its predecessor's `gate_passed` flag.
- `plan` requires **every** signed-off story to be covered by some iteration.
- `design` requires a rendered HTML whose embedded sha256 matches the current
  markdown — you cannot approve a design nobody could look at, or a stale one.
- `implement` **fails** if `pytest`/`ruff`/`behave` are needed but missing; set
  `HARNESS_ALLOW_MISSING_TOOLS=1` to skip explicitly.
- `release` requires every PRD checkbox checked and every iteration verified.

## Rendering diagrams

```bash
bash ~/.claude/skills/mermaid-render/render.sh --shared-lib \
  -o docs/iterations/ITER-01.html --title "ITER-01 Design" docs/iterations/ITER-01.md
```

The page embeds the source's sha256, which is what the `design` gate checks for
freshness.

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
`docs/WORKFLOW_CHANGES.md`: a `meta-NNNN-*.md` ADR, user sign-off, version bump.

## Tools required

- `bash`, `jq`, mikefarah `yq` **v4** (the gate library rejects python-yq)
- `pytest`, `ruff` — when `src/` exists
- `behave` (or any Gherkin runner) — for `tests/features/*.feature`

Install: `winget install MikeFarah.yq jqlang.jq` (Windows), `brew install yq jq`
(macOS). Python tools via `pip install behave pytest ruff`.

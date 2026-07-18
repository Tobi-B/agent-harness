# Lean Harness v0

Documentation-driven agent workflow with executable gates. The agent interviews, drafts, asks for approval, and only then advances. Architecture decisions require explicit user sign-off (human-in-the-loop).

**Trust model**: gates are pure checks the agent may run freely; approvals and phase transitions are user actions the agent cannot forge. Sign-offs are sha256-hashed — editing a signed-off artifact invalidates its sign-off.

## How to run

1. Read `workflow.yaml` — single source of truth for phases and gates.
2. Fill `docs/prd.md` (the NFR section is mandatory; the gate checks it).
3. Run the agent through the phases: `discover → architect → model → implement → verify`.
4. Per artifact the agent drafts, **you** approve by running `bash gates/signoff.sh <path>`.
5. Check a phase anytime with `bash gates/<phase>.sh` (pure, no side effects; CI-safe).
6. Advance with `bash gates/advance.sh <phase>` — runs the gate, writes the audit file, updates `status.yaml`, moves `current_phase`. This is the phase transition, so **you** run it (or explicitly tell the agent to use `--yes`).

## Files

| Path | Purpose |
|---|---|
| `workflow.yaml` | Phases, gates (`run:` + enforced `checks:`), hardcaps, agent loop. |
| `dor_dod.yaml` | Definition of Ready / Done per phase (human checklist; subset machine-enforced). |
| `status.yaml` | Live state: current phase, gate history, sign-off registry (path + sha256 + by + at). |
| `docs/prd.md` | Goals, Non-Goals, Success Criteria, NFRs. |
| `docs/architecture.md` | C4 architecture + cross-cutting concerns. |
| `docs/adrs/README.md` | MADR template + 3-ADR hardcap. `meta-*.md` = workflow ADRs, exempt from the cap. |
| `docs/uml/README.md` | C4 + sequence + state templates + traceability rule. |
| `docs/user_stories/README.md` | Story format + 1:1 `.feature` linkage. |
| `docs/WORKFLOW_CHANGES.md` | Meta-loop for changing the harness itself. |
| `templates/feature.template` | Gherkin skeleton (outside `tests/features/` so behave never picks it up). |
| `tests/features/*.feature` | Gherkin acceptance tests, 1:1 with stories. |
| `tests/gates/test_gates.sh` | Self-tests for the gates (run locally or in CI). |
| `gates/<phase>.sh` | Pure phase checks — no state mutation. |
| `gates/signoff.sh` | **User-run**: records artifact sign-off (sha256) in `status.yaml`. |
| `gates/advance.sh` | **User-run**: gate + audit + status update + phase transition. |
| `audit/*.md` | Phase audit trail, written by `advance.sh`. |

## Agent loop

```
interview → draft → user signs off (signoff.sh) → gate passes → user advances (advance.sh)
```

User approval required for: phase transitions, every ADR, changes to signed-off artifacts, exceptions to hardcaps. The agent never runs `signoff.sh`, and runs `advance.sh --yes` only on explicit user instruction.

## Hardcaps

Defined once in `workflow.yaml` (`hardcaps:`); gates read them from there.

- Max 3 ADRs in v0 (`gates/architect.sh`).
- Max 20 user stories per `discover` run (`gates/discover.sh`).
- Single concurrent story in `implement`.

## Gate strictness

- Every criterion listed under `gate.checks:` in `workflow.yaml` is enforced by the script — nothing declared-but-unchecked.
- Each gate requires its predecessor's `gate_passed` flag.
- `implement` **fails** if `pytest`/`ruff`/`behave` are needed but missing; set `HARNESS_ALLOW_MISSING_TOOLS=1` to skip explicitly.
- `verify` requires every PRD checkbox (`- [ ]`) to be checked (`- [x]`) or removed.

## Testing the harness itself

```
bash tests/gates/test_gates.sh   # fixture-based self-tests (awk regression, tamper detection, advance flow)
shellcheck -x gates/*.sh tests/gates/*.sh
```

Both run in CI: `.github/workflows/harness-ci.yml`.

## Meta-loop

Changes to `workflow.yaml`, `gates/`, `dor_dod.yaml`, or templates must go through `docs/WORKFLOW_CHANGES.md`: draft a `meta-NNNN-*.md` ADR, user sign-off, version bump.

## Tools required

- `bash`, `jq`, mikefarah `yq` **v4** (the gate library rejects python-yq) — gates
- `pytest`, `ruff` — when `src/` exists
- `behave` (or any Gherkin runner) — for `tests/features/*.feature`

Install: `winget install MikeFarah.yq jqlang.jq` (Windows), `brew install yq jq` (macOS). Python tools via `pip install behave pytest ruff`.

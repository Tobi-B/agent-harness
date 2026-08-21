---
id: meta-0001
status: partially superseded by meta-0004 (sign-off registry; pure gates and advance flow stand)
date: 2026-07-18
references:
  - WORKFLOW_CHANGES.md
sign-off:
  by: user
  at: 2026-07-18 (approved in chat)
---

# meta-0001 Pure gates, verifiable sign-off, enforced-only criteria

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`).

## Context and Problem Statement

A review of harness v1 found: (a) `has_frontmatter_field` always returned
failure (awk `exit 0` in a rule still runs `END`, whose `exit 1` overrides),
so the discover/architect gates could never pass; (b) the audit trail was
declared everywhere but `write_audit` was never called; (c) gates mutated
`status.yaml` and auto-advanced `current_phase`, contradicting the rule that
phase transitions require user approval; (d) sign-off was agent-editable
frontmatter and therefore forgeable; (e) many gate criteria in
`workflow.yaml` were declared but enforced by no script; (f) missing test
tools produced a warning and a passing gate.

## Decision Drivers

- A harness that governs an agent must not be forgeable by that agent.
- Declared checks that are not enforced train the agent to satisfy the
  script, not the contract.
- Gates must be safe to run repeatedly (CI) without side effects.

## Considered Options

1. No change — keep v1 behavior.
2. Patch the awk bug only, keep architecture as-is.
3. Restructure: gates become pure checks; `signoff.sh` (user-run, sha256
   registry in `status.yaml`) is the only approval authority; `advance.sh`
   (user-run, interactive confirm) is the only phase transition and writes
   the audit; every declared criterion is enforced or removed; missing tools
   fail the `implement` gate unless `HARNESS_ALLOW_MISSING_TOOLS=1`;
   hardcaps are read from `workflow.yaml`; self-tests + shellcheck + CI
   guard the gates themselves.

## Decision Outcome

Chosen option: 3, because options 1–2 leave the trust model broken: an agent
could still self-approve and self-advance, and the declared/enforced gap
would persist.

### Consequences

- Good: sign-offs are tamper-evident (hash mismatch fails the gate);
  transitions are auditable and user-controlled; gates are idempotent; the
  gates themselves are tested (`tests/gates/test_gates.sh`) and linted.
- Bad: slightly more ceremony — the user must run `signoff.sh` per artifact
  and `advance.sh` per phase; local dev needs mikefarah yq v4.

### Confirmation

`bash harness/tests/gates/test_gates.sh` (19 checks, including the awk
regression, tamper detection, purity of gates, and the advance flow) plus
`shellcheck -x` — both wired into CI (`.github/workflows/harness-ci.yml`).

## More Information

Changelog entry v2 in `WORKFLOW_CHANGES.md`. Meta ADRs use the `meta-NNNN-`
prefix so `gates/architect.sh` (which globs `000*.md`) does not count them
against the project ADR hardcap.

---
id: meta-0006
status: accepted
date: 2026-09-21
approved_by: user (2026-11-11, in chat)
references:
  - meta-0001-pure-gates-and-verifiable-signoff.md
  - meta-0004-trusted-approval-markers.md
  - meta-0005-full-autopilot-except-release.md
---

# meta-0006 Close silent-pass holes; make the implement gate stack-neutral

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). Approved after the fact: the machinery shipped as v7 on
2026-11-09 while this ADR was still `proposed`; the user approved it on
2026-11-11. `tools/check-repo.sh` now fails CI when a live version has no
approved ADR, so that order cannot repeat unnoticed.

## Context and Problem Statement

A review of v6 against its own promise — *gates that cannot be talked past* —
found places where a gate passed, or the machine moved, without the thing it
guards being true. Each was reproduced before being fixed:

1. **Templates self-approve.** The story format ships
   `approved_by:   # left empty in drafts …`. `approved_by_of` returned the
   comment text, which is non-empty, so an untouched draft counted as approved.
   So did `""`, `TBD`, `pending`, `no`.
2. **implement checks the wrong directory.** It looked for `$HARNESS_ROOT/src`,
   i.e. `harness/src`, while the project's code lives next to `harness/`. On a
   real project it printed `INFO: no src/ … skipping` and passed — no tests,
   no lint, no TODO scan.
3. **The TODO scan skipped comments.** `^[^#]*\b(TODO|FIXME)\b` excludes any
   line with a `#` before the marker, i.e. every Python comment TODO.
4. **advance.sh accepted any phase.** Advancing an already-passed earlier phase
   rewound `current_phase` and cleared `current_iteration`.
5. **The autopilot budget stranded its last iteration.** The budget check ran
   before every phase, so the iteration that spent the last unit stopped after
   `design`; `--max-iterations 1` could not complete one iteration.
6. **advance.sh plan failed ~40% of the time.** `first_iteration_id` piped into
   `head -1` under `pipefail`; yq got SIGPIPE (exit 141) and advance died
   silently after `PASS: plan`. The v6 self-test suite failed 13 of 30 runs.
7. **Windows checkouts broke everything.** With the default
   `core.autocrlf=true`, gate scripts die on line 2 (`pipefail\r`) and CRLF
   frontmatter hides every approval marker.

Separately, `implement` hard-coded pytest / ruff / behave, so any non-Python
project had to either edit a gate (meta change) or opt out of all checks.

## Decision Drivers

- A gate that passes because it looked in the wrong place is worse than no
  gate: it produces a false audit trail.
- The approval marker is the one trust point in the design (meta-0004); its
  parser must not widen that trust.
- Per-project tooling is project work and should not need a meta ADR.
- Every fix must come with a test that fails on v6.

## Considered Options

1. **No change** — keep v6.
2. Fix the defects only; leave implement Python-only.
3. **Fix the defects and move the implement commands into a project-owned
   `harness/project.yaml`, keeping pytest / ruff / behave as the Python default.**

## Decision Outcome

Chosen option: 3. Option 1 leaves holes that defeat the harness's core claim.
Option 2 keeps the most common reason to hand-edit a gate.

- Approval: allowlist `user` / `autopilot` (optional trailing note); inline
  YAML comments and quotes are stripped; the `# approved_by:` comment form is
  read only in `.feature` files.
- implement: runs `commands.test|lint|acceptance` from `project.yaml` in the
  project root; scans `source_dirs` for TODO/FIXME including comments. No
  source / empty command / missing tool fails unless
  `HARNESS_ALLOW_MISSING_TOOLS=1`; a failing command is never downgraded.
- advance.sh: only the current phase; a passed once-phase cannot be re-advanced.
- Autopilot: an iteration already claimed is finished even on a spent budget;
  expiry still stops everything.
- No `| head` on unguarded pipes; CR-tolerant parsing; installer writes
  `.gitattributes` (LF) and normalises copied files; bash >= 4 check with a
  clear message; portable `rel_to_root`.

### Consequences

- Good: each listed hole has a regression test that fails on v6; the suite is
  deterministic (0 of 30 runs failing, from 13 of 30).
- Good: C++/JUCE, TypeScript, etc. work by editing `project.yaml` only.
- Bad: stricter by default. A non-Python project that never fills in
  `project.yaml` now fails `implement` instead of passing it silently —
  intentionally.
- Bad: placeholder approval values that used to pass (`approved_by: tester`)
  are now drafts; existing artifacts with such values must be re-approved.

### Confirmation

`bash harness/tests/gates/test_gates.sh` — 107 checks, including one per
defect above and a 50-call loop for the SIGPIPE race.

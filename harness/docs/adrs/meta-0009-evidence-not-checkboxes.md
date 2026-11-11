---
id: meta-0009
status: proposed
date: 2026-11-11
approved_by:
references:
  - meta-0006-hardening-and-stack-neutral-implement.md
  - meta-0007-pull-based-slices-and-subagent-per-story.md
  - meta-0008-decision-gated-autonomy.md
---

# meta-0009 Evidence, not checkboxes: gates that run, and decided artifacts that stay decided

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). Proposed; nothing under `workflow.yaml` or `gates/`
changes before the user approves it.

## Context and Problem Statement

v8 gives the owner the mode they asked for: they decide, the agent builds, and
an open question stops the machine. What v8 does not yet guarantee is that what
the loop reports while nobody watches is *true*, and that what the owner
decided *stays* decided. Each gap below is read from the code at v8.

1. **`verify` grades itself.** `verify.sh` reads the `## Verification` section
   and counts checkboxes. It runs nothing. The agent writes the boxes; the
   code may have changed since `implement` passed.
2. **`release` grades itself.** `release.sh` counts checked boxes in the PRD
   and looks for three headings in `verify-report.md`. It runs nothing either.
   The test suite is never run against the release as a whole.
3. **Acceptance runs every feature, from the first iteration on.**
   `implement.sh` runs `commands.acceptance` over all of `tests/features/`.
   In ITER-01 the steps of later stories do not exist yet, and behave and
   cucumber report undefined steps as failures. A project with more than one
   iteration cannot pass `implement` honestly — the only ways out are to stub
   steps or to narrow the command by hand. The pilot run would hit this in its
   first iteration.
4. **Decided artifacts can change without a decision.** Under `build` the agent
   approves nothing, but nothing stops it from editing a story, a feature file,
   an ADR, `plan.md` or `project.yaml` after the owner approved it. v8 lists
   that as a reason to open a decision — an instruction. The gates of
   once-phases never run again, so nothing would notice.
5. **The escape hatch is the agent's to open.** `HARNESS_ALLOW_MISSING_TOOLS=1`
   is an environment variable. Whoever runs the gate sets it — under autopilot,
   the agent.
6. **Coming back to a loop means digging.** What happened since autopilot was
   switched on is spread over `audit/`, `docs/decisions/`, the iteration files
   and `git log`.
7. **The PRD carries no approval.** Every other artifact the owner decides has
   an `approved_by:` marker; the document that everything traces back to does
   not.

meta-0008 deferred these "until a real project has run end to end on v8".
Gap 3 changes that: it would stop that run in ITER-01 for a reason that has
nothing to do with the project.

## Decision Drivers

- A gate that the agent can satisfy by writing text is a checklist, not a gate
  (meta-0001: list only what a script enforces).
- Unattended means: when the owner comes back, what the machine says happened
  is what happened.
- Decisions change through a decision — the inbox v8 introduced — not through
  an edit.
- Lean: no new state machine, no cache, no hashes (meta-0004). Reuse git,
  which every installation already has, and the markers that exist.
- What can only be an instruction is called an instruction.

## Considered Options

1. **Nothing before the pilot** — run the pilot on v8, decide afterwards.
2. **Evidence** — `verify` and `release` run the project commands; acceptance
   covers only the stories that are due; the escape hatch moves into
   `project.yaml`; the PRD gets a marker. (Gaps 1, 2, 3, 5, 7.)
3. **Evidence + tripwire + report** — 2, plus: under autopilot, a change to a
   decided artifact stops the machine unless an answered decision covers it;
   and a pure `gates/report.sh`. (All gaps.)
4. **3 + permission rules** — 3, plus Claude Code `ask` rules for
   `advance.sh release` and `autopilot.sh on`, installed by `init.sh`.

## Decision Outcome

Proposed: **option 3**.

Option 1 runs the pilot into gap 3 and measures a defect instead of the
workflow. Option 2 makes the loop's claims true but leaves the owner's
decisions unguarded exactly when they are not watching — the case `build`
exists for. Option 3 closes that with git and the decisions inbox, both already
there, and the report is what the owner reads after the pilot, so it pays for
itself in the first run. Option 4's rules are a speed bump, not a lock — a
different spelling of the command (`./harness/...`, `cd harness && ...`) is
not matched — and they need a merge into an existing `.claude/settings.json`;
whether that is worth it is something the pilot can show.

### What changes

**`verify` and `release` run the commands.** The command runner moves from
`implement.sh` into `_lib.sh` (`run_project_commands`). `verify.sh` runs test,
lint and acceptance for the stories that are due, then checks the
`## Verification` section as before — the boxes become the agent's account,
the commands the evidence. `release.sh` runs them for every story. No result is
cached: a gate re-runs the suite every time it is asked, which costs time and
is the only answer that cannot go stale.

**Acceptance covers what is due.** The gates export to every project command:

| variable | content |
|---|---|
| `HARNESS_DUE_STORIES` | story ids of every iteration up to and including the current one, in plan order (`US-001 US-002`) |
| `HARNESS_DUE_FEATURES` | the matching `tests/features/US-*.feature` paths, relative to the project root |

Earlier iterations stay in, so acceptance is also a regression check.
`release` sets both to every planned story. The Python fallback becomes
`behave $HARNESS_DUE_FEATURES`; a configured command uses the variable or
ignores it — `project.yaml` is project-owned. Feature filenames must not
contain spaces (they never do from the template).

**The escape hatch belongs to the project.** `project.yaml` gets
`allow_missing_tools: false`. The environment variable keeps working for a human
at a terminal, but is ignored while autopilot carries the phase: under
autopilot, only the file counts — and the file is guarded by the tripwire.

**The PRD is approved like everything else.** `docs/prd.md` gets frontmatter
with `approved_by:`; the `**Status**: draft | approved` line goes, so there is
one vocabulary. The discover gate checks the marker last (exit 3). An existing
installation past `discover` is unaffected — once-phase gates do not re-run.

**Tripwire: decided artifacts change only through a decision.**
`autopilot.sh on` records `autopilot.base_commit` (`git rev-parse HEAD`).
`autopilot_block_reason` — the predicate `advance.sh` and `next.sh` share —
then compares the working tree against that commit, committed and uncommitted
changes and new untracked files alike, for the **decided paths**:

- `docs/prd.md`, `docs/plan.md`, `docs/architecture.md`
- `docs/user_stories/US-*.md`, `tests/features/US-*.feature`
- `docs/adrs/*.md` (project and meta)
- `project.yaml`, `workflow.yaml`, `dor_dod.yaml`, `gates/`, `templates/`

A changed path is **covered** if a decision with a valid `approved_by:`
references it: by id for stories, features and ADRs (`US-003` covers
`US-003-*.md` and `US-003-*.feature`, `ADR-0002` covers `0002-*.md`), by file
name otherwise (`plan.md`, `project.yaml`). An uncovered change stops autopilot
like an open decision: `next.sh` exits 3 and names the files. The way on is
either a decision the owner answers, or — if they simply accept the change —
switching autopilot on again, which moves the base.

Iteration designs are not on the list: the agent drafts them under autopilot,
and the design gate already refuses an unapproved one. *Editing a design after
it was approved stays an instruction-level rule.* Without git, or with a v8
`status.yaml` that has no `base_commit`, the tripwire is off and
`autopilot.sh status` says so.

**`gates/report.sh` — what happened while I was away.** Pure, read-only. Since
`autopilot.enabled_at`: the transitions (from `audit/`, with their `via` line),
decisions opened and answered, the iteration `## Notes`, commits
(`git log --oneline base..HEAD`), and the current `next.sh` verdict. No new
state; it reads what is already written.

**Tests.** A regression test for each of the above, including: verify fails
when the code broke after implement passed; ITER-01 acceptance does not see
ITER-02's features; release sees all of them; the environment hatch is ignored
under autopilot; a story edited under autopilot stops `next.sh`, an answered
decision referencing it clears the stop, re-enabling clears it too; no git →
tripwire off and reported.

### Not in this ADR

- Permission rules (option 4) — after the pilot.
- meta-0007's ordered backlog — after the pilot, as planned.
- An upgrade path for existing installations (`init.sh --force` replaces
  project state) — separate.

### Consequences

- Good: no gate in the iteration cycle passes on the agent's word alone; the
  suite runs at `implement`, `verify` and `release`.
- Good: multi-iteration projects can pass `implement` without stubbed steps.
- Good: what the owner decided is guarded by a check while they are away, and
  the way to change it is the inbox that already exists.
- Good: one command tells the owner what happened.
- Bad: the suite runs more often — every time `next.sh` asks the `verify` or
  `release` gate. Slow suites make ticks slow.
- Bad: answering a decision that changes an artifact now needs the decision to
  reference it, or a re-enable. That is friction by design.
- Bad: one more status field (`base_commit`), one more script (`report.sh`),
  two new environment variables in the command contract.
- Neutral: the tripwire is only as honest as the `approved_by:` on the
  decision that covers a change — the same trust boundary as every marker
  (meta-0004).

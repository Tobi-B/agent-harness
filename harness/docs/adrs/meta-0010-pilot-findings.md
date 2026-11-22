---
id: meta-0010
status: proposed
date: 2026-11-22
approved_by:
references:
  - meta-0008-decision-gated-autonomy.md
  - meta-0009-evidence-not-checkboxes.md
---

# meta-0010 What the pilot showed: a way back from release, designs that name their interfaces and NFRs, an expiry that does not strand a run

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). **Proposed** — nothing in `workflow.yaml` or `gates/`
changes until the user approves it (set `status: accepted` and
`approved_by: user`).

meta-0007 (pull-based slices) was withdrawn by the owner on 2026-11-22 and its
file deleted; its text stays in git history. Its subagent-per-story half
already lives in `AGENTS.md` since v8; this ADR takes what the pilot showed is
worth changing, and nothing the pilot did not show.

## Context and Problem Statement

The pilot (`mdcheck`, v9, three iterations, auto mode `build`) ran end to end:
ITER-01 and ITER-02 without the owner, ITER-03 after the owner approved its
design, one decision, one owner-approved release, tripwire never tripped. Four
frictions were real — each cost a stop, a workaround or a late discovery — and
are recorded in the pilot's `PILOT_NOTES.md`.

1. **No way back from `release`.** Release preparation measured 37 s against a
   3 s performance NFR. The fix is an iteration's worth of work, but
   `advance.sh` only advances the current phase and `status.yaml` is never
   edited by hand, so there is no ITER-04. The owner chose to carry the fix
   inside the release phase (DEC-001) — a deviation from the phase machine,
   made because the machine offered no honest alternative.
2. **NFRs are first measured at `release`.** No design or verify step asks
   which NFR an iteration touches or how it is measured. The 37 s was found
   after all three iterations had passed.
3. **Designs do not name interfaces.** Two subagents invented signatures
   (`anchors_of`, `Finding.kind`) because the approved design described
   behaviour but not the function boundary. The invention was sound, but it
   was a decision the owner did not see — and cold subagents cannot know each
   other's choices.
4. **Autopilot's wall-clock expiry strands a run.** With a one-iteration
   budget, autopilot expired while a single subagent was implementing
   (hours of clock time), so the `implement → verify` transition came back to
   the owner and autopilot had to be restarted. The budget already lets a
   claimed iteration finish (meta-0006); the expiry does not.

Smaller items from the same notes are not decisions and are listed under "Not
in this ADR".

## Decision Drivers

- Change only what the pilot made necessary. Seven versions in four months
  swung between positions without being measured on a real run; this ADR is
  the first one that is.
- The owner decides, the agent builds: a way back must be the owner's call,
  never autopilot's.
- Gates list only what a script enforces (meta-0001). A heading that must
  exist is enforceable; "the interfaces are good" is not.
- The brake against runaway loops stays mechanical (meta-0005, meta-0008's
  `--phase-timeout`).

## Considered Options

1. **Nothing** — keep v9; workarounds like DEC-001 stay ad hoc.
2. **The four fixes above** (this ADR's core).
3. **Core plus the ordered backlog** from meta-0007: `plan.md` gets a
   `backlog:` list next to the iterations.
4. **A bigger rework** (slices, ITER→SLICE rename) — rejected with meta-0007:
   the pilot's three iterations fitted the three stories and the rename
   touches the state shape, four gates, templates, tests and docs for a gain
   the pilot did not show.

## Decision Outcome

Proposed option: **2**. Option 3 is available as an add-on if the owner wants
it — see its weak evidence below.

### 1. `advance.sh reopen` — back from `release`, by decision only

When `current_phase` is `release` and `release` has not passed, the **user** can
run `bash harness/gates/advance.sh reopen`. It succeeds only when:

- an answered decision (`approved_by: user`) that **references `plan.md`**
  exists and is newer than the last release attempt, and
- `plan.md` now lists at least one iteration whose `design`, `implement` and
  `verify` gates have not passed (the new iteration the decision asked for).

It then sets `current_phase: design` and `current_iteration` to the first such
iteration, in one atomic write like every other transition, and the audit
records `via reopen (DEC-NNN)`. Autopilot never carries it (`release` stays
the user's); the tripwire already treats `plan.md` as decided, and the
referencing decision is the way to change it. `plan.sh` is re-run at `design`
as usual, so coverage is checked again. The `release` phase's own
`started_at`/`gate_passed` are reset when `release` is entered again.

### 2. Design template: `## Interfaces` and `## NFR impact`

`iteration.template.md` gains two sections above `## Test Strategy`:

- **Interfaces** — names and signatures of every function or type that crosses
  a module boundary in this iteration (new or changed), or the words "none".
- **NFR impact** — which PRD NFRs this iteration can affect and how each is
  measured here, or the words "none".

`design.sh` fails when either heading is missing or its body is empty. The
content stays a human-readable approval item: the owner sees it in the design
review and can overrule it; the gate only guarantees the question was
answered.

### 3. Expiry stops new iterations, never a claimed one

`advance.sh` and `next.sh` treat an expired autopilot like an exhausted budget:
no **new** iteration is claimed, but the claimed iteration's
`design → implement → verify` transitions are still carried. The expiry still
ends the run at the next iteration boundary; `--phase-timeout` still hands a
stalled phase back. Cost: the hard stop is now "at the end of the claimed
iteration", not "immediately" — a run can overshoot `--expires` by the length
of one iteration.

### 4. (Option 3 only) Ordered `backlog:`

`plan.md` frontmatter gets an optional `backlog: [US-003, US-001, …]`; `plan.sh`
checks every approved story appears exactly once and every referenced story
exists. Iterations stay as they are; the backlog is the owner's priority
order for what to pull into the *next* iteration. **Evidence from the pilot:
none** — the three iterations were planned correctly up front. It is listed
because the owner asked for it in the original review; skipping it costs
nothing now and it can follow when a real project reorders work.

### Confirmation

Extend `tests/gates/test_gates.sh`, one check per claim:

- `reopen` refuses with no answered decision referencing `plan.md`, with an
  unanswered one, with a decision older than the last release attempt, with an
  unchanged plan, and under autopilot; it succeeds with all of them in place
  and leaves `current_phase: design`, the new iteration current, an audit entry
  with `via reopen (DEC-NNN)`, and the release phase reset.
- `design` fails without `## Interfaces`, without `## NFR impact`, and with
  either empty; passes with "none".
- An expired autopilot with a claimed iteration still advances `design`,
  `implement`, `verify` of that iteration and refuses to claim another.
- (Option 3) a backlog listing a story twice, or missing an approved one,
  fails `plan`.

### Not in this ADR

Small items from the pilot that need no decision, or live outside the gates:

- the `model` gate leaves no approval marker in a file (the user's word is
  recorded only in the audit) — noted, left as is;
- the design review page shows diagrams but not the design text — a change to
  the `mermaid-render` skill, not to the gates;
- `init.sh`'s `.gitattributes` pins LF only for `harness/**`; adding `src/`-type
  paths is a template change that can go with this version's template edits if
  the owner agrees;
- `report.sh` reprints subagent notes verbatim and is long — a nit.

### Consequences

- Good: a release-time finding can become an iteration, honestly, through a
  decision the owner answered; no more bending the phase machine.
- Good: NFRs and interfaces are asked for at design time, when the owner
  looks anyway; the answer is visible rather than invented by a subagent.
- Good: an autopilot run is not stranded by a long tick; the hard stop moves
  to a boundary where nothing is half done.
- Bad: designs get longer; "none" is a cheap answer and can be rubber-stamped.
  The gate cannot tell a good answer from a lazy one.
- Bad: `advance.sh` gains a second kind of command (`reopen`), and the phase
  machine gains its first backward edge — more state paths to test and to
  explain.
- Bad: the expiry becomes softer: `--expires` is no longer an exact stop.
- Neutral: option 3's backlog is optional and independent of the rest.

---
id: meta-0007
status: proposed
date: 2026-11-10
approved_by:
references:
  - meta-0002-iteration-cycle-and-visual-design-gate.md
  - meta-0005-full-autopilot-except-release.md
  - meta-0006-hardening-and-stack-neutral-implement.md
---

# meta-0007 Pull-based slices, and a fresh subagent per story

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). **Proposed** — takes effect when the user who owns the
workflow approves it (set `status: accepted` and `approved_by: user`).

## Context and Problem Statement

Two independent problems, both in the iteration cycle.

**Context accumulates across an iteration.** `implement` already serialises to
one story at a time (`hardcaps.max_concurrent_stories_in_implement: 1`), but
all of an iteration's stories are implemented inside one agent session. By the
third story the context holds the first two stories' exploration, dead ends and
tool output. Quality degrades exactly where it is least recoverable — in
delivered code — and nothing in the harness notices, because the gates check
the result, not how clearly it was arrived at.

Everything a *cold* agent would need is already on disk: `prd.md`, the ADRs,
`architecture.md`, the UML diagrams, the iteration design, and the `.feature`
file carrying the acceptance criteria. meta-0006 closed the last gap by moving
the test/lint/acceptance commands into `project.yaml`, so a fresh agent no
longer has to infer the stack. The documentation-driven premise is what makes
cold context viable here; the harness simply has not been cashing it in.

**`plan` demands an up-front partition.** It groups every approved story into
exactly one `ITER-NN`, and `gates/plan.sh` enforces total coverage. That
coverage check is the traceability net and is worth keeping. The *partition* is
not: committing all ~20 stories to fixed iterations before the first line of
code is the most waterfall-shaped part of the harness, and reprioritising means
re-approving the plan.

## Decision Drivers

- Context should be fresh per story; the artifacts are the context.
- The `design` gate is the only mechanism in the harness that forces a human to
  actually look at something (meta-0002). Its cost per story must not rise —
  leverage comes from it being rare enough to take seriously.
- Starting work should not require partitioning the whole backlog.
- Approval authority stays with the user. A subagent cannot be asked for
  approval, so it must never write an `approved_by:` marker.
- The autopilot brake stays mechanical (meta-0005): trust covers honesty, not
  runaway loops.

## Considered Options

1. **No change** — keep v7's planned iterations and single-session implement.
2. **Flat backlog, everything per story** — drop iterations; `design`,
   `implement` and `verify` each run once per story.
3. **Pull-based slices + subagent per story** — `plan` produces an *ordered
   backlog*; `design` pulls the next few unstarted stories and reviews them as
   one slice; `implement` spawns a fresh subagent per story in that slice;
   `verify` closes the slice.
4. **Subagents only** — keep planned iterations exactly as they are, and change
   nothing but the rule that each story gets a fresh subagent.

## Decision Outcome

Chosen option: **3**.

Option 2 is the tempting one and it is a trap. It multiplies the design gate
from at most 12 reviews to as many as 20, each needing a rendered diagram and
an explicit approval. More approvals is not more control — it is the reliable
way to manufacture rubber-stamping, which costs the harness the one checkpoint
that cannot be replaced by a script.

Option 4 solves context rot but leaves the up-front partition, which is the
part that actually constrains how the work can be reordered.

Option 3 separates two things that v7 conflates onto one axis:

| | Unit |
|---|---|
| Human design approval | the **slice** |
| Agent implementation | the **story** |

Concretely:

- **`plan`** produces an ordered backlog in `docs/plan.md` frontmatter
  (`backlog: [US-003, US-001, …]`) instead of an iteration partition. Gate:
  every approved story appears exactly once, every referenced story exists, the
  plan carries its marker. Drops `iteration_ids_match_ITER_NN_and_are_unique`
  and `iteration_count_within_hardcap`.
- **`design`** becomes `scope: slice`. The agent pulls one or more *unstarted*
  stories, writes `docs/slices/SLICE-NN.md` naming exactly those, renders it,
  and asks for approval. Backlog order is **priority guidance, not binding** —
  the agent may group related stories that are not adjacent. The invariant is
  preserved at the other end instead (see `release` below), which keeps the
  traceability net without freezing the order.
- **`implement`** becomes `scope: slice` and implements each of the slice's
  stories in a **fresh subagent**, one at a time, which is already the
  serialisation v7 mandates. The subagent may run gates freely; it must not
  write `approved_by:` markers and must not run `advance.sh`.
- **`verify`** becomes `scope: slice`.
- **`release`** additionally requires that every story in the backlog has
  passed `verify` in some slice. This is where total coverage is now enforced.
- **`status.yaml`**: `iterations: {}` → `slices: {}`, keyed `SLICE-NN`, each
  recording its story list and gate flags.
- **hardcaps**: `max_iterations` → `max_slices`; add `max_stories_per_slice`
  (3 proposed) so a slice stays reviewable in one sitting.
- **autopilot**: `max_iterations` → `max_slices`, same brake semantics.

### Consequences

- Good: fresh context per story, without raising the number of human approvals.
- Good: no up-front partition; reprioritising is editing an ordered list.
- Good: total story coverage still enforced, just at `release` instead of
  `plan`.
- Good: the slice design doc becomes the shared contract several cold
  subagents implement against — a concrete use for an artifact that previously
  only informed one session.
- Bad: **cold context cuts both ways.** Story N's subagent does not know the
  convention decisions story M's subagent made inside the same slice. The
  gates cannot catch the resulting architectural drift, because both variants
  are green. The slice design and `architecture.md` mitigate it; requiring the
  subagent to read existing source before writing mitigates it further.
  Neither eliminates it, and this is a real cost of the option, not a detail.
- Bad: **portability regression.** `AGENTS.md` is meant to work for any agent
  (opencode, Aider, Cursor, Continue). Spawning subagents is not universally
  available, so the contract needs a documented fallback: a single-session
  agent implements the slice's stories sequentially and is told that the
  freshness requirement is unmet. The harness must not silently appear to have
  a property it does not have.
- Bad: higher token cost — each subagent re-reads the governing documents.
- Bad: `ITER-NN` → `SLICE-NN` touches `status.yaml`'s shape, `advance.sh`, four
  gates, the templates, the self-tests, `AGENTS.md`, both agent skills and the
  glue commands. Any installation mid-flight needs a migration.

### Confirmation

Extend `tests/gates/test_gates.sh`, one check per claim:

- a backlog listing a story twice fails `plan`
- a backlog missing an approved story fails `plan`
- a slice naming a story that is not in the backlog fails `design`
- a slice naming an already-verified story fails `design`
- a slice exceeding `max_stories_per_slice` fails `design`
- `advance.sh verify` loops to `design` while unstarted stories remain, and
  reaches `release` only when none do
- `release` fails while any backlog story has not passed `verify`

The subagent-per-story rule is a **convention**, not machine-checkable — the
gates cannot see how many sessions produced a diff. It is listed under
`agent_actions`, alongside `use_idempotency_keys_per_architecture_md`, and must
not be listed under `gate.checks:`, which would violate the enforced-only rule
from meta-0001.

## Pros and Cons of the Options

### Option 1 — no change

- Good: nothing to migrate; the machine is proven and its self-tests are green.
- Bad: context rot in `implement` is unaddressed.
- Bad: the up-front partition stays.

### Option 2 — flat backlog, everything per story

- Good: simplest machine; `scope: iteration` disappears entirely.
- Good: flatter state (`stories.<US-NNN>` instead of nested iterations).
- Bad: up to 20 design reviews instead of at most 12 — see Decision Outcome.
- Bad: loses the grouping in which a change is designed as one coherent whole.

### Option 3 — pull-based slices + subagent per story

- Good / Bad: as under Consequences.
- Neutral: a slice of one story is allowed, so option 2's behaviour remains
  reachable per slice without being imposed.

### Option 4 — subagents only

- Good: smallest diff by far; no state migration, no gate rewrites.
- Good: solves context rot, which is the more damaging of the two problems.
- Bad: leaves the up-front partition and the re-approval cost of reordering.
- Neutral: a sensible first step if the rename is judged too expensive for now
  — it is forward-compatible with option 3.

## More Information

Extends meta-0002 (which introduced the iteration cycle and the visual design
gate) and depends on meta-0006 for `project.yaml`: without project-owned test,
lint and acceptance commands, a cold subagent would have to infer the stack,
which is precisely the inference meta-0006 removed.

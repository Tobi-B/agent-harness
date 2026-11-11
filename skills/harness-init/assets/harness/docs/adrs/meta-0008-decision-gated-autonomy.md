---
id: meta-0008
status: accepted
date: 2026-11-11
approved_by: user (2026-11-11, in chat — option 3, `full` stays as an opt-in)
references:
  - meta-0003-bounded-autopilot.md
  - meta-0004-trusted-approval-markers.md
  - meta-0005-full-autopilot-except-release.md
  - meta-0006-hardening-and-stack-neutral-implement.md
  - meta-0007-pull-based-slices-and-subagent-per-story.md
---

# meta-0008 Decision-gated autonomy: the human decides, the agent builds

Meta ADR (workflow change, exempt from the project ADR hardcap — see
`WORKFLOW_CHANGES.md`). Approved by the user before any change to
`workflow.yaml` or `gates/` was made.

## Context and Problem Statement

The owner's goal for the harness is: *I am involved in the important decisions,
and the implementation runs largely by itself, in a loop.* v7 offers two modes
and neither is that one.

- **Auto off**: the human approves every artifact *and* every transition,
  including the routine ones inside an iteration.
- **Auto on** (meta-0005): the agent approves everything itself — stories, ADRs,
  the plan, every design — and only `release` waits.

meta-0003 had described the goal almost word for word ("the decisions worth a
human's attention are concentrated in `discover`, `architect`, `model`, `plan`
and `release` — not in each iteration's grind") and warned that a configurable
scope "would drift toward 'all'". meta-0005 went to "all" in one step. No ADR
has considered *the human decides, the agent executes*.

Four further gaps stand between v7 and a loop that can be left alone:

1. **No way to ask.** A question that comes up mid-implementation — the design
   no longer fits, a dependency is needed, a story cannot be built as written —
   has no home. Nothing lets the agent park it and nothing makes the machine
   wait for the answer.
2. **No "what now?".** Every tick re-derives the next action from prose and
   four files. `/harness` is written as one interactive step; the loop is one
   sentence in a skill file.
3. **`autopilot.sh status` contradicts `advance.sh`.** Once an iteration has
   spent the last unit of budget, `status` exits 1 ("used its budget") while
   `advance.sh` still carries that iteration to its end. `AGENTS.md` tells the
   agent to stop when `status` says so — so `--max-iterations 1` stops after
   `design`, the bug meta-0006 fixed in the gate, back at the instruction level.
4. **Mechanical defects** (each reproduced by reading the code):
   - `advance.sh` writes `status.yaml` in about eight separate steps and sets
     `current_phase` last. An interruption in between leaves a once-phase
     passed but still current, and `advance.sh` then refuses it for good.
   - Writing `approved_by:` into an iteration file makes it newer than its
     render, so every design approval forces a re-render before the gate passes.
   - `advance.sh <phase> --yes` is recorded in the audit as "approved by: user".
     The harness cannot know who asked.
   - `.autopilot.scope` is written and never read. Two code comments still
     describe the meta-0003 scope.

## Decision Drivers

- Decisions and execution are different kinds of work. The dial should separate
  them, not phases.
- More approvals is not more control (meta-0007). The human should be asked
  rarely, and then about something real.
- A loop needs one primitive it can ask, with an answer a script can act on.
- Honesty about mechanism versus instruction (meta-0004): what a gate enforces
  is listed as a check; what only the agent's word guarantees is called that.
- Lean: reuse the marker, the gates and the budget that exist. No new state
  machine, no second approval scheme.

## Considered Options

1. **No change** — keep v7's two modes.
2. **Back to meta-0003** — autopilot covers `design`/`implement`/`verify` and
   approves iteration designs itself.
3. **Two named modes, fixed in code** — `build` (new default): autopilot carries
   *transitions* of `design`/`implement`/`verify` and never approves anything.
   `full`: today's behaviour, explicit opt-in.
4. **`build` only** — as 3, and `full` and `approved_by: autopilot` are removed.

## Decision Outcome

Chosen option: **3**. Option 4 was offered as the leaner alternative at
approval; the owner kept `full`.

Option 1 leaves the goal unmet. Option 2 hands over the one checkpoint the owner
has asked to keep: the design gate is the only place the harness makes a human
look at something. Option 3 is meta-0003's scope minus machine approval, and it
answers meta-0003's own worry — two named modes fixed in code are not a
configurable scope. Option 4 is simpler still, but removes a capability the
owner asked for in meta-0005.

### What changes

**Modes.** `autopilot.sh on [--mode build|full]`, default `build`, stored as
`autopilot.mode`. A missing field means `build`.

| | `build` | `full` |
|---|---|---|
| auto-advance | `design`, `implement`, `verify` | every phase except `release` |
| `approved_by: autopilot` counts | never | while autopilot is on and unexpired |
| `release` | human | human |

`approval_is_valid` is where the mode is enforced: in `build` only `user` is an
approval, so the `design` gate passes only for a design the human approved —
a check in the gate, not a rule in a prompt. Markers written under `full` stay
in the files as an honest record; once-phase gates never re-run, so only
artifacts whose gate has not passed yet start waiting for the user.

**Designs ahead.** No new machinery: `design.sh` reads only the current
iteration's file, so the human may approve the designs of the next N iterations
in one sitting and the loop then runs N iterations unattended. The runway is
bounded by the iteration budget. If an approved design no longer fits the code
when its turn comes, that is a decision (below), not an edit. *This last rule is
an instruction, not a mechanism* — staleness of a design is not detectable.

**Decisions.** `docs/decisions/DEC-NNN-<slug>.md` — Question, Options with the
agent's recommendation, Decision — carrying the same `approved_by:` marker as
every other artifact. A decision without a valid marker is *open*. That is the
whole format: no status field, no priority, no second vocabulary.

- While any decision is open, autopilot carries nothing and `release` fails.
- The agent opens one when: an artifact the user approved would have to change;
  an architectural choice is not covered by an ADR (dependency, schema, public
  interface, security); a story cannot be built as specified; a command in
  `project.yaml` would change or `HARNESS_ALLOW_MISSING_TOOLS` would be set; a
  hardcap would be exceeded; something is irreversible or leaves the machine.
  *The trigger list is an instruction; that an open decision stops the machine
  is a mechanism.*
- Small reversible choices the agent makes itself go into the iteration's
  `## Notes`.

**`gates/next.sh` — "what now?"** Pure. Prints phase, iteration, gate result,
autopilot state, one action and what is waiting for the human.

| exit | meaning |
|---|---|
| 0 | a loop may tick: `work` (gate red) or `advance` (gate green and carried) |
| 3 | the human's move: an approval, an open decision, a transition that is theirs, a stall |
| 4 | done |
| 2 | environment broken |

To tell "work needed" from "waiting for the human" without parsing messages,
gates run every structural check first and the approval checks last, and exit
**3** instead of 1 when the only thing missing is the human's word.
`next.sh` and `advance.sh` share one predicate (`autopilot_block_reason`), and
`next.sh` never computes where the machine goes next — a test asserts that it
says `advance` exactly when `advance.sh` would succeed.

`autopilot.sh status` stops being a decision input: it reports whether autopilot
is on and unexpired; the agent asks `next.sh`.

**Stall brake.** `autopilot.sh on --phase-timeout 2h` (off by default).
`next.sh` compares now against the later of the phase's `started_at`, which
`advance.sh` already records, and `autopilot.enabled_at`. A gate that is still
red after that long is reported as the human's move. A gate that turns green
still advances. This is a finer-grained expiry, not a measure of effort, and it
needs no new mutator.

**The tick.** `/harness` becomes: run `next.sh`; on `work` do one unit — in
`implement`, one story in a fresh subagent where the tool has subagents; commit;
on `advance` run `advance.sh`; on exit 3 show what is waiting, notify, and stop.
A subagent never writes an approval marker and never runs `advance.sh`. The
rules live once, in `AGENTS.md`; the commands and skills point there.
*One subagent per story is a convention* (`agent_actions`, not `gate.checks`) —
it is the part of meta-0007 worth taking now, its own option 4.

**Defects fixed in the same change**

- `advance.sh` applies a transition as one `yq` expression.
- An approved design is not re-checked for render freshness; an unapproved one
  with a stale render still fails.
- The audit records `via: interactive | --yes | autopilot(<mode>)`.
- `autopilot.sh on` writes an audit entry; re-enabling resets budget and stall
  clock, and that should leave a trace.
- `.autopilot.scope` is removed; the stale comments are corrected.

### Not in this ADR

Deliberately left for a second ADR, after a real project has run end to end on
v8: gates that execute instead of checking checkboxes (`verify`, `release`),
`HARNESS_DUE_FEATURES` so acceptance runs only the stories that are due, a run
report, a tripwire for changes to decided artifacts, a PRD approval marker, and
meta-0007's ordered backlog.

### Consequences

- Good: the mode the owner asked for exists, and its boundary is a gate check.
- Good: the loop has one question to ask and a script-readable answer.
- Good: a mid-flight question stops the machine instead of being decided
  silently — using the marker that already exists.
- Good: `full` can no longer be entered by accident; it has to be named.
- Bad: one more concept (decisions), one more script (`next.sh`), one more exit
  code. Each replaces something that was prose before.
- Bad: under `build` the loop stops at every design that was not approved
  ahead. That is the point, and it is also the cost.
- Bad: an installation mid-flight with `approved_by: autopilot` on artifacts
  whose gate has not passed must have them approved by the user, or re-enable
  with `--mode full`.
- Unchanged: the trust model. An agent can still write `approved_by: user`
  itself; nothing here claims otherwise.

### Confirmation

`bash harness/tests/gates/test_gates.sh`, one check per claim, each failing on
v7:

- the exit-3 contract for `discover`, `architect`, `plan`, `design`;
- an `autopilot` marker is a draft when autopilot is off, in `build`, and after
  `full` expires; it counts in `full`; a status file without `mode` is `build`;
- real walks through `advance.sh` with no `--yes`: `build` advances a
  user-approved design and refuses an unapproved or autopilot-approved one;
  once-phases never auto-advance in `build`; a claimed iteration finishes on a
  spent budget and `autopilot.sh status` stays on meanwhile;
- an open decision pauses auto-advance and fails `release`; approving it
  releases both;
- `next.sh` is pure, agrees with `advance.sh` in at least four states, names
  the design waiting for approval, reports a stall, still advances a green gate
  after the timeout, and exits 4 after release;
- a failed status write leaves `status.yaml` byte-identical;
- the audit records `--yes` as `--yes`.

Plus one manual run: scaffold a small project, approve two designs in one
sitting, enable `build` with a budget of two, run `/loop /harness`. Expected:
both iterations run alone and no file carries `approved_by: autopilot`.

## Pros and Cons of the Options

### Option 1 — no change

- Good: nothing to migrate.
- Bad: the owner's goal is not reachable in either mode.

### Option 2 — back to meta-0003

- Good: smallest diff; the scope already existed.
- Bad: iteration designs are approved by the agent — the checkpoint the owner
  wants to keep.

### Option 3 — `build` default, `full` opt-in

- Good / Bad: as under Consequences.

### Option 4 — `build` only

- Good: one mode, no `approved_by: autopilot`, no mode-dependent validity; the
  allowlist shrinks to `user`.
- Bad: removes the "hand over a whole throwaway project" capability of
  meta-0005; existing `autopilot` markers on unpassed artifacts need the user.

## More Information

Supersedes meta-0005 in scope and default (budget, expiry, chat enablement and
audit marking stand). Takes the subagent-per-story convention from meta-0007;
with that part landed, meta-0007's remaining proposal — the ordered backlog and
the ITER→SLICE rename — should be decided after the first real run, and is
better served by keeping the `ITER-NN` ids than by renaming them.

Migration for a v7 installation: `status.yaml` needs no edit (a missing `mode`
is `build`); create `harness/docs/decisions/`; find markers that now wait with
`grep -rlE '^(#[[:space:]]*)?approved_by:[[:space:]]*autopilot' harness/docs
harness/tests/features`.

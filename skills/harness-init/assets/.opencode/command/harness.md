---
description: Run the next step of the harness loop from the current phase
---

Drive the lean harness one step forward.

## 1. Orient (always, before anything else)

Read, in this order:

1. `harness/status.yaml` — `current_phase`, `current_iteration`, `signed_off_artifacts`
2. `harness/workflow.yaml` — the phase contract (`agent_actions`, `gate`, `next`)
3. `harness/dor_dod.yaml` — the readiness checklist for that phase
4. The artifacts the current phase `produces:` — what already exists
5. `harness/docs/plan.md` — when in or past `plan`, this is the iteration list

Then run the current phase's gate to see where you actually stand:

```
bash harness/gates/<current_phase>.sh
```

Gates are pure checks — run them freely. The failure message names the exact
missing thing.

## 2. Report

Tell the user in two or three lines: current phase (and iteration), what the
gate says, and what the next concrete step is. If `$ARGUMENTS` was given, treat
it as the user's instruction for this step.

## 3. Do the next step

Work the phase per its `agent_actions` in `workflow.yaml`:

- **interview** the user where the phase calls for it — ask focused questions,
  a handful at a time, not a questionnaire.
- **draft** artifacts into the exact paths under `produces:`.
- **render** — in `model` and `design`, turn the Mermaid into a page the user
  can actually look at:
  ```
  bash ~/.claude/skills/mermaid-render/render.sh -o <out>.html --title "<title>" <sources>
  ```
  Then show it with `SendUserFile` (`display: "render"`). Never ask for design
  approval without showing the rendered diagram first.
- **ask for sign-off** — tell the user which command to run:
  ```
  bash harness/gates/signoff.sh <artifact>
  ```
- **re-run the gate** until it passes.

## 4. Hand back

When the gate passes, stop and ask the user to advance:

```
bash harness/gates/advance.sh <phase>
```

## Hard rules

- **Never** run `signoff.sh` yourself. Sign-off is the user's act; the registry
  is hash-verified, so a forged entry fails the gate anyway.
- **Never** run `advance.sh --yes` unless the user explicitly told you, in this
  conversation, to advance this phase.
- **Never** edit `harness/status.yaml` directly.
- Editing a signed-off artifact invalidates its sign-off — say so, and ask for
  a fresh one.
- If a gate fails twice for the same reason, stop and escalate instead of
  guessing.
- Changing the harness itself (`workflow.yaml`, `gates/`, `dor_dod.yaml`) goes
  through `harness/docs/WORKFLOW_CHANGES.md`: a `meta-NNNN-*.md` ADR, user
  sign-off, version bump.

## The shape of the loop

```
discover → architect → model → plan → ⟳(design → implement → verify) → release
```

`design`, `implement`, and `verify` are iteration-scoped: they run once per
iteration in `plan.md`, and `advance.sh verify` either loops back to `design`
for the next iteration or moves on to `release`.

$ARGUMENTS

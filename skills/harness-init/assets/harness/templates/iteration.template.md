---
id: ITER-NN
status: draft | approved
approved_by:
references:
  - US-001
  - ADR-0001
---

<!-- approved_by stays empty in drafts. The agent fills in 'user' after the
     user approves the rendered design in chat ('autopilot' only under an
     active autopilot budget). The design gate fails while it is empty. -->

# ITER-NN <Title>

Covers stories: US-001, US-002   <!-- must match docs/plan.md for this iteration -->

## Goal

One sentence: the user-visible value this iteration delivers.

## Approach

Which pattern(s), which components change, why this way and not the obvious
alternative. Reference the ADRs that constrain the choice.

```mermaid
%% sources: US-001, ADR-0001
sequenceDiagram
  autonumber
  actor User
  participant Component
  User->>Component: action
  Component-->>User: result
```

<!-- Add a class diagram, state diagram, or flowchart if the change warrants it.
     Every ```mermaid block lands on the rendered review page. -->

## Affected Components

| Component | Change | C4 ref |
|---|---|---|
|  |  | `uml/c4-component.mmd` |

## Test Strategy

- Unit: ...
- Acceptance: scenarios from `tests/features/US-NNN-*.feature`
- What could break elsewhere, and how we would notice.

## Verification

<!-- Filled during the `verify` phase. Report on EVERY story listed above.
     The gate rejects unchecked boxes in this section. -->

- [ ] US-001 — all scenarios pass
- [ ] US-002 — all scenarios pass

## Notes

Open questions, follow-ups, deliberate deferrals.

---
# The iteration list is the machine-readable contract. gates/plan.sh validates
# it and gates/advance.sh walks it. Every approved story must appear in
# exactly one iteration's `stories:` list.
iterations: []
# iterations:
#   - id: ITER-01
#     goal: One sentence — the user-visible value this iteration delivers.
#     stories: [US-001, US-002]
#   - id: ITER-02
#     goal: ...
#     stories: [US-003]
---

# Iteration Plan

**Status**: draft | approved
**Companion to**: PRD (`prd.md`), Architecture (`architecture.md`)

Slice the work into small **vertical** iterations: each one delivers testable
user value on its own, rather than a horizontal layer (all models, then all
views). Prefer more, smaller iterations over few large ones.

## Iterations

| ID | Goal | Stories | Definition of Done |
|---|---|---|---|
| ITER-01 |  |  |  |
| ITER-02 |  |  |  |

Keep this table in sync with the frontmatter above — the frontmatter is what the
gate reads.

## Sequencing rationale

Why this order? Which iteration de-risks the most uncertain part first?

## Out of scope for this plan

- 

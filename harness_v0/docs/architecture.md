# Architecture

**Status**: draft | approved
**Companion to**: PRD (`prd.md`), ADRs in `adrs/`, Diagrams in `uml/`
**Format**: C4 model (Context → Containers → Components → Code) + Cross-Cutting Concerns

## Context (Level 1)

Who uses the system, and what other systems does it talk to? One paragraph, then the diagram.

[Context diagram](uml/c4-context.mmd)

## Containers (Level 2)

What deployable units / processes / apps make up the system? One paragraph, then the diagram.

[Container diagram](uml/c4-container.mmd)

## Components (Level 3)

What are the major modules inside each container? One paragraph per container, then the diagram.

[Component diagram](uml/c4-component.mmd)

## Code (Level 4)

For each non-trivial component: classes, functions, public interfaces. Skip for small projects. Reference `uml/c4-code-<component>.mmd` per component when used.

## Tech Choices

| Concern | Choice | Rationale | ADR |
|---|---|---|---|
| Language |  |  |  |
| Runtime |  |  |  |
| Storage |  |  |  |
| Communication |  |  |  |
| AuthN/AuthZ |  |  |  |

## Cross-Cutting Concerns

### Idempotency

Every state-changing operation carries an idempotency key derived from `(agent_id, task_id, action, params)`. Duplicate keys are no-ops. A `behavior_key` (action+params hash) detects repeated *logical* actions across iterations and aborts the agent loop. The `implement` gate rejects duplicate logical actions.

### Audit Trail

Phase boundaries commit a markdown audit file under `audit/` (one per phase, timestamped). Status fields in `status.yaml` carry the same information for tooling.

### Observability

Every state transition emits a structured log entry (key/value). User-facing operations emit RED metrics (Rate, Errors, Duration). Trace context is propagated across component boundaries where supported.

### Error Handling

| Category | Example | Handling |
|---|---|---|
| Transient | network timeout | exponential backoff, bounded retries |
| Permanent | 4xx input | fail fast, surface to caller |
| Contract violation | unknown action | halt loop, write audit, ask user |

### Security

Secrets never in code or logs. All endpoints auth-checked. Threat model reviewed and signed off as an NFR in `prd.md`.

## Sequence and State Diagrams

For each key user flow (referenced in story acceptance criteria) see `uml/sequence-<flow>.mmd`. For each lifecycle (PRD or ADR) see `uml/state-<entity>.mmd`.

## Open Questions

-
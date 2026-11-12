---
approved_by:
---

<!-- approved_by stays empty in drafts. The agent writes 'approved_by: user'
     only after the user approved the PRD in chat. The discover gate waits
     (exit 3) while it is empty. -->

# Product Requirements Document

**Owner**: 
**Last updated**: 

## Problem

Who has what problem today, and why does it matter?

## Goals

- 
- 

## Non-Goals

- 
- 

## Users / Actors

- **Actor**: role and context
- **Actor**: role and context

## User Stories

See `user_stories/INDEX.md`. Each story has a 1:1 Gherkin `.feature` file under `tests/features/`.

## Success Criteria

Measurable, time-boxed outcomes. The `verify` gate checks each of these against the implementation.

- [ ] measurable, time-boxed
- [ ] 
- [ ] 

## Non-Functional Requirements

NFRs are first-class. Each item must be measurable and becomes a check in the `verify` gate. Add only categories that apply to your project.

### Performance

- [ ] p95 latency ≤ X ms for operation Y
- [ ] throughput ≥ X ops/sec

### Reliability

- [ ] availability ≥ X% over rolling 30 days
- [ ] RPO ≤ X min, RTO ≤ X min

### Security

- [ ] all secrets via vault, never in code
- [ ] threat model reviewed and accepted by owner
- [ ] no HIGH/CRITICAL findings from `bandit` / `trivy` / equivalent

### Observability

- [ ] structured logs for all state transitions
- [ ] metrics for all user-facing operations (RED or USE)
- [ ] trace context propagated across components

### Maintainability

- [ ] test coverage ≥ X% on critical paths
- [ ] no function longer than X lines
- [ ] cyclomatic complexity ≤ X

### Cost

- [ ] infra cost ≤ $X/month at target load

## Constraints

- runtime, language, platform, security, budget

## Assumptions

- 
-
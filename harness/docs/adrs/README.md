# Architecture Decision Records

Each ADR captures one load-bearing decision. v0 caps the count at **3** (hardcap in `workflow.yaml`, enforced by `gates/architect.sh`). Workflow ADRs (`meta-NNNN-*.md`, see `../WORKFLOW_CHANGES.md`) are exempt from the cap.

## Format (MADR)

Filename: `NNNN-short-slug.md`. Frontmatter + body.

```markdown
---
id: 0001
status: proposed | accepted | superseded
date: YYYY-MM-DD
references:
  - PRD §Goals
  - US-003
---

# 0001 <Title>

## Context and Problem Statement

What forces this decision? Which goal, NFR, or user story is affected?

## Decision Drivers

- driver 1
- driver 2

## Considered Options

1. Option A — one-line description
2. Option B — one-line description
3. Option C — one-line description

## Decision Outcome

Chosen option: X, because ...

### Consequences

- Good: ...
- Bad: ...

### Confirmation

How do we know the decision was right? Which tests, metrics, or behaviors prove it?

## Pros and Cons of the Options

### Option A

- Good: ...
- Bad: ...
- Neutral: ...

### Option B

- Good: ...
- Bad: ...

## More Information

Links, references, related ADRs (use `supersedes: 0000` if replacing).
```

## Process

1. Agent drafts the ADR with `status: proposed` and at least two options with tradeoffs.
2. User decides; agent sets `status: accepted`.
3. User signs off by running `bash gates/signoff.sh docs/adrs/NNNN-<slug>.md` — this records the file's sha256 in `status.yaml`. The registry is the approval authority; frontmatter is informational.
4. Gate `gates/architect.sh` checks `status: accepted`, the MADR sections, and that the recorded hash matches the current file content (edits after sign-off fail the gate).
5. Hardcap enforced: a 4th ADR is rejected unless the hardcap is relaxed in `workflow.yaml`.

## Hardcap

If a fourth load-bearing decision emerges, the agent must either:

- merge it into an existing ADR, or
- escalate to the user to relax the hardcap.

No silent fourth ADR.
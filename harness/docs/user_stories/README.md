# User Stories

One story = one acceptance contract. The story is the human-readable spec; a Gherkin `.feature` file is the executable contract. Both are first-class and live 1:1.

## Format

Filename: `US-NNN-short-slug.md`. Frontmatter + body.

```markdown
---
id: US-001
status: draft | approved
approved_by:            # left empty in drafts; the agent writes 'user' after approval in chat
references:
  - PRD §Goals
  - ADR-0001
feature: tests/features/US-001-short-slug.feature
---

# US-001 <Title>

**Role**: <who>
**Want**: <what>
**So that**: <why>

## Acceptance Criteria

- [ ] <criterion 1> — implemented as a `Scenario` in `tests/features/US-001-*.feature`
- [ ] <criterion 2>
- [ ] <criterion 3>

## Notes

<open questions, dependencies, edge cases>
```

The matching Gherkin feature file:

```gherkin
# approved_by:   <- the agent writes '# approved_by: user' after approval in chat
@US-001
Feature: <story title>

  As a <role>
  I want <want>
  So that <so that>

  Scenario: <criterion 1>
    Given <precondition>
    When <action>
    Then <expected outcome>

  Scenario: <criterion 2>
    Given <precondition>
    When <action>
    Then <expected outcome>
```

## Process

1. Agent interviews for role / want / so-that per actor.
2. Agent drafts the story plus the matching `.feature` file with one `Scenario` per Acceptance Criterion (skeleton: `templates/feature.template`).
3. User approves **both** files in conversation. The agent then writes `approved_by: user` into the story's frontmatter and a `# approved_by: user` comment into the `.feature` file — only after, never before, the user actually said so.
4. The `discover` gate rejects stories or `.feature` files without an `approved_by:` marker, and missing `.feature` files. If a file changes materially after approval, ask the user again before keeping the marker.

## INDEX

Maintain `INDEX.md` here. One row per story: ID, title, status, feature path, approval.

```markdown
| ID | Title | Status | Feature | Approved |
|---|---|---|---|---|
| US-001 | ... | approved | tests/features/US-001-...feature | user, 2026-01-15 |
```
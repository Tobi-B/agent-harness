# User Stories

One story = one acceptance contract. The story is the human-readable spec; a Gherkin `.feature` file is the executable contract. Both are first-class and live 1:1.

## Format

Filename: `US-NNN-short-slug.md`. Frontmatter + body.

```markdown
---
id: US-001
status: draft | approved
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
3. User signs off **both** files: `bash gates/signoff.sh docs/user_stories/US-NNN-<slug>.md` and `bash gates/signoff.sh tests/features/US-NNN-<slug>.feature`. This records each file's sha256 in `status.yaml` — the registry is the approval authority; the frontmatter `status:` field is informational.
4. The `discover` gate rejects unsigned stories, missing `.feature` files, and any file edited after sign-off (hash mismatch).

## INDEX

Maintain `INDEX.md` here. One row per story: ID, title, status, feature path, sign-off timestamp.

```markdown
| ID | Title | Status | Feature | Signed off |
|---|---|---|---|---|
| US-001 | ... | approved | tests/features/US-001-...feature | 2026-01-15 |
```
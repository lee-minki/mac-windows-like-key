# Task System

## 1. Purpose

Use this file to split implementation work into checkable units.

A task is valid only if it has:

- scope
- deliverable
- acceptance conditions
- verification step
- commit checkpoint

---

## 2. Task Split Rules

### Rule T1. Split by concern

Do not mix these concerns in one task unless required:

- trigger simplification
- docs cleanup
- stabilization changes
- VDI validation
- screen-sharing validation
- terminal/Claude Code fixes
- hook/tooling setup

### Rule T2. Split by proof point

Create a new task boundary whenever a result can be independently verified.

Examples:

- Right Option removed from UI
- stale F19 docs removed
- hook path added and executable
- one test target added and passing

### Rule T3. Split by rollback safety

If a change can be reverted independently, it should be its own task and commit checkpoint.

---

## 3. Checklist Format

Each implementation task must use this format:

```markdown
- [ ] Task title
  - Goal:
  - Files:
  - Deliverable:
  - Acceptance Conditions:
    - AC1:
    - AC2:
  - Verification:
  - Commit Checkpoint:
```

---

## 4. Commit Checkpoint Rules

Set commit checkpoints only where the result is confirmable.

### Good commit checkpoints

- docs updated and internally consistent
- Right Option removed from visible product surface
- hook system added and runnable
- test target added and green
- one bug reproduction converted from fail to pass

### Bad commit checkpoints

- half-finished architecture refactor
- mixed docs + runtime + unrelated cleanup without proof

---

## 5. Acceptance Condition Rules

Each task must include concrete ACs.

### Good AC examples

- AC: settings UI no longer exposes Right Option
- AC: no doc claims `Caps Lock -> F19` as active current behavior
- AC: pre-commit hook exits non-zero on failing build/test

### Bad AC examples

- AC: works better
- AC: seems stable
- AC: cleaner code

---

## 6. Task Status Rules

Allowed statuses:

- `pending`
- `in_progress`
- `blocked`
- `completed`

### Update rules

1. Only one task may be `in_progress` at a time.
2. Mark a task `completed` immediately after its verification succeeds.
3. Mark a task `blocked` if progress depends on unresolved context validation.
4. If a task grows beyond one verifiable checkpoint, split it before continuing.

---

## 7. Split Review Rule

After first-pass planning, review the task list using these questions:

1. Does any task touch more than one concern?
2. Does any task lack a binary verification step?
3. Does any task require more than one commit checkpoint?
4. Does any task hide an unresolved context question?

If yes, split again.

---

## 8. Initial Implementation Breakdown

- [ ] Task 1: document set cleanup and index linking
  - Goal: make the split design set the active source of truth
  - Files: `docs/design/*`, parent spec, README/doc links as needed
  - Deliverable: docs set exists and points to the correct source files
  - Acceptance Conditions:
    - AC1: split design docs exist
    - AC2: parent spec and index links are valid
  - Verification: read-back and link review
  - Commit Checkpoint: `docs: add split redesign documents`

- [ ] Task 2: remove Right Option from product surface
  - Goal: remove user-visible Right Option support
  - Files: settings UI, app state, help/docs
  - Deliverable: Right Command is the only visible trigger
  - Acceptance Conditions:
    - AC1: no settings UI exposes Right Option
    - AC2: docs no longer describe Right Option as supported
  - Verification: code read + UI read + diagnostics/build
  - Commit Checkpoint: `refactor: remove Right Option trigger path from product surface`

- [ ] Task 3: remove stale F19 / Caps Lock drift
  - Goal: align docs/help with actual Caps Lock ownership
  - Files: README, setup docs, VDI docs, help, doctor text
  - Deliverable: no stale F19 relay claims remain as current behavior
  - Acceptance Conditions:
    - AC1: Caps Lock described as system-owned
    - AC2: F19 relay not claimed as current unless implemented and proven
  - Verification: grep and doc review
  - Commit Checkpoint: `docs: align Caps Lock and VDI behavior descriptions`

- [ ] Task 4: add test and verification foundation
  - Goal: create a TDD-capable baseline for the redesign
  - Files: test target, supporting test files, workflow docs
  - Deliverable: at least one runnable automated test path exists
  - Acceptance Conditions:
    - AC1: test target exists
    - AC2: documented test command runs successfully
  - Verification: test command exit code 0
  - Commit Checkpoint: `test: add baseline verification target for IME workflow`

- [ ] Task 5: add repo-local hook system
  - Goal: enforce build/test/doc gates before commit or push
  - Files: `.githooks/*`, docs, setup instructions
  - Deliverable: tracked hooks with install/setup docs
  - Acceptance Conditions:
    - AC1: repo has active tracked hook scripts
    - AC2: hook setup command is documented
  - Verification: executable hooks + dry-run
  - Commit Checkpoint: `chore: add tracked git hook workflow`

- [ ] Task 6: reproduce and fix terminal / Claude Code issue
  - Goal: eliminate Right Command prompt pollution in terminal-like environments
  - Files: transport/stabilization path, tests/docs/logging rules
  - Deliverable: reproduction converted to pass or isolated with explicit rule
  - Acceptance Conditions:
    - AC1: reproduction steps are documented
    - AC2: prompt pollution no longer occurs or is explicitly isolated by context rule
  - Verification: manual repro + logs
  - Commit Checkpoint: `fix: stabilize Right Command switching in terminal-like contexts`

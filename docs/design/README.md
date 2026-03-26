# Design Document Index

## Purpose

This folder splits the IME switching redesign into focused documents.

Use this folder before changing code, docs, hooks, or tests.

## Document Order

1. [`01_REQUIREMENTS.md`](./01_REQUIREMENTS.md)
   - product requirements
   - scope and non-goals
   - acceptance criteria by context

2. [`02_ARCHITECTURE.md`](./02_ARCHITECTURE.md)
   - runtime model
   - context resolution
   - transport selection
   - stabilization pipeline

3. [`03_BEHAVIOR_MATRIX.md`](./03_BEHAVIOR_MATRIX.md)
   - scenario-by-scenario expected behavior
   - known issues
   - verification status

4. [`04_TASK_SYSTEM.md`](./04_TASK_SYSTEM.md)
   - task split rules
   - checklist rules
   - commit checkpoints
   - acceptance condition rules

5. [`05_DEVELOPMENT_RULES.md`](./05_DEVELOPMENT_RULES.md)
   - TDD workflow
   - Git hook rules
   - CI/build/test/lint rules
   - mandatory doc update rules

6. [`06_DEBUGGING.md`](./06_DEBUGGING.md)
   - logging strategy
   - reproduction rules
   - log filtering script requirements

7. [`07_REGRESSION_NOTES.md`](./07_REGRESSION_NOTES.md)
   - regressions that must not be reintroduced
   - forbidden design patterns
   - terminal/Ghostty lessons learned

## Parent Spec

This folder expands:

- [`../RIGHT_COMMAND_ONLY_SPEC.md`](../RIGHT_COMMAND_ONLY_SPEC.md)

If this folder conflicts with the parent spec, update both in the same change.

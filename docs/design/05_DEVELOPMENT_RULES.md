# Development Rules

## 1. TDD Rule

Implementation must follow this order whenever feasible:

1. define or update the scenario in `03_BEHAVIOR_MATRIX.md`
2. write or update a failing test, harness, or reproduction record
3. implement the smallest change that satisfies the scenario
4. run verification
5. update docs in the same change

If a fully automated test is not possible for a context-sensitive keyboard path, replace step 2 with a written reproduction harness and explicit manual AC.

---

## 2. Test Strategy

The repo currently has no test target.

The redesign must introduce testability in layers:

### Layer A — pure logic tests

- context resolution
- trigger policy
- state transitions
- replay timing decisions where decoupled from macOS event APIs

### Layer B — integration harness

- buildable verification target
- explicit reproduction scripts/checklists for runtime-only issues

### Layer C — manual validation

- local macOS
- Windows VDI
- remote Mac / screen sharing
- terminal / Claude Code

---

## 3. Git Hook Rule

### Decision

Do **not** adopt Husky as the default hook system for this repo.

Reason:

- Husky assumes a Node.js toolchain
- this repo is a native Swift/Xcode project with no existing Node workflow
- a repo-local tracked hook directory is simpler and better aligned

### Required approach

Use tracked repo-local hooks via:

- `.githooks/`
- `git config --local core.hooksPath .githooks`

### Minimum target hooks

- `pre-commit`
- `pre-push`

### Optional later hooks

- `commit-msg`

---

## 4. Hook Gates

### Pre-commit

Minimum responsibilities:

- fail on obvious malformed docs/state mismatch checks
- run fast validation only
- if docs are required by the change, fail when docs are not updated

### Pre-push

Minimum responsibilities:

- run build
- run tests
- run lint/format check if those tools are introduced

### Rule

Do not put slow, flaky, full-environment validation into `pre-commit`.

Put heavier checks in `pre-push` or CI.

---

## 5. Build / Test / Lint Policy

### Build

Current known build command:

```bash
xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey -configuration Debug -derivedDataPath build/DerivedData build
```

### Tests

- add an XCTest target when practical
- until then, provide an equivalent baseline automated verification harness for non-UI logic
- document the exact test command after the harness exists

Current baseline command:

```bash
scripts/run-tests.sh
```

### Lint / format

Current repo has no configured SwiftLint or SwiftFormat.

Design rule:

- if lint/format are introduced, they must be documented and added to hook/CI rules in the same change

---

## 6. Mandatory Documentation Update Rule

Any change in these categories must update docs in the same change:

- user-visible behavior
- setup or permission flow
- transport path
- trigger ownership
- debugging workflow
- hook/build/test workflow

If a commit changes behavior but does not update required docs, the commit is not complete.

---

## 7. CI Rule

Current repo has release CI only.

The redesign should add a non-release validation workflow later with these stages:

1. docs checks
2. build
3. tests
4. optional lint/format checks if configured

Until then, local hooks carry the minimum enforcement burden.

---

## 8. Commit Rule

Each commit must correspond to a verification point.

Commit only when:

- AC is satisfied
- required docs are updated
- relevant validation commands are green

Examples:

- `docs: add redesign architecture and workflow set`
- `refactor: remove Right Option trigger surface`
- `chore: add tracked git hook workflow`
- `test: add baseline IME workflow target`

---

## 9. Review Rule

Before merging or handing off implementation work, verify:

- the behavior matrix was updated
- the task checklist status is current
- the docs still match actual runtime ownership boundaries

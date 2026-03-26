# Implementation Plan

## 1. Planning Rule

This plan is derived from:

- `docs/RIGHT_COMMAND_ONLY_SPEC.md`
- `docs/design/01_REQUIREMENTS.md`
- `docs/design/02_ARCHITECTURE.md`
- `docs/design/03_BEHAVIOR_MATRIX.md`
- `docs/design/04_TASK_SYSTEM.md`
- `docs/design/05_DEVELOPMENT_RULES.md`
- `docs/design/06_DEBUGGING.md`

Do not implement outside this plan without updating the design docs first.

---

## 2. Status Legend

- [ ] pending
- [-] in progress
- [x] completed
- [!] blocked

Only one item may be `in progress` at a time.

---

## 3. Phase Checklist

## Phase 1 — Documentation alignment

- [x] P1-1 Add design doc index and split documents
  - AC:
    - design docs exist
    - links are valid
  - Commit checkpoint: docs set exists and is internally consistent

- [x] P1-2 Align parent spec with split docs
  - AC:
    - no contradictions between parent spec and split docs
  - Commit checkpoint: parent spec and split docs read consistently

- [x] P1-3 Remove stale current-behavior claims about Right Option and F19
  - AC:
    - no doc claims Right Option is supported
    - no doc claims `Caps Lock -> F19` is current behavior without proof
  - Commit checkpoint: grep-based review passes

## Phase 2 — Trigger simplification

- [x] P2-1 Remove Right Option from settings/UI
  - AC:
    - no visible trigger selector shows Right Option
  - Commit checkpoint: UI and help read Right Command only

- [x] P2-2 Remove Right Option branching from app state/runtime config
  - AC:
    - Right Command is the only supported trigger path
  - Commit checkpoint: runtime config paths simplified

## Phase 3 — Verification foundation

- [x] P3-1 Add automated test target or equivalent baseline harness
  - AC:
    - a documented test command exists
    - the baseline target runs successfully
  - Commit checkpoint: test foundation is runnable

- [x] P3-2 Add tracked git hook system
  - AC:
    - `.githooks/` exists
    - local setup command is documented
  - Commit checkpoint: hook scripts are executable and documented

- [x] P3-3 Add validation workflow rules for build/test/doc updates
  - AC:
    - pre-commit and pre-push responsibilities are documented and implemented or queued clearly
  - Commit checkpoint: workflow rules are enforceable

## Phase 4 — Runtime stabilization

- [x] P4-1 Revalidate local macOS switching
  - AC:
    - build passes after Right Command-only cleanup
    - baseline automated verification is green
  - Commit checkpoint: local verification result recorded

- [ ] P4-2 Revalidate Windows VDI switching
  - AC:
    - F16 relay path is verified
    - no ghost shortcut regression in target scenarios
  - Commit checkpoint: VDI verification result recorded

- [ ] P4-3 Reproduce and isolate terminal / Claude Code issue
  - AC:
    - exact reproduction exists
    - logs are filtered and attached in compact form
  - Commit checkpoint: issue is reproducible and scoped

- [ ] P4-4 Fix terminal / Claude Code issue
  - AC:
    - Right Command no longer emits prompt pollution in the validated reproduction
  - Commit checkpoint: fail -> pass conversion recorded

## Phase 5 — Unknown context closure

- [ ] P5-1 Validate remote Mac / screen-sharing path
  - AC:
    - path is either verified or explicitly documented as open
  - Commit checkpoint: behavior matrix updated with evidence

---

## 4. Split Review

This plan was reviewed for over-large tasks.

### Review result

- documentation alignment is split from runtime changes
- trigger simplification is split from verification foundation
- terminal/Claude Code is isolated as its own workstream
- screen sharing remains separate because it is still unknown

### Remaining rule

If any task needs more than one binary proof point, split it again before implementation.

---

## 5. Auto-Update Rule

Update task status automatically using these triggers:

- move `pending -> in progress` when the first file edit or validation step for that task begins
- move `in progress -> completed` immediately after AC verification succeeds
- move `in progress -> blocked` immediately when progress depends on unresolved context or missing infrastructure
- if a task is split, mark the parent item completed only after child items are created and tracked

---

## 6. Required Evidence Per Phase

| Phase | Evidence |
|---|---|
| Docs | read-back review + grep review |
| Trigger simplification | diagnostics/build + UI/doc review |
| Verification foundation | test/build command exit code 0 |
| Runtime stabilization | reproduction record + filtered logs + pass/fail update |
| Unknown context closure | explicit verification record |

---

## 7. Commit Sequence Recommendation

1. `docs: add split design and workflow documents`
2. `docs: align Right Command-only and Caps Lock behavior text`
3. `refactor: remove Right Option trigger surface`
4. `test: add baseline verification target`
5. `chore: add tracked git hook workflow`
6. `fix: reproduce and stabilize terminal-like switching`
7. `docs: record remote context verification results`

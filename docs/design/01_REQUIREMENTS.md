# IME Switching Redesign Requirements

## 1. Objective

Redesign and stabilize WinMac Key around a single trigger model:

- **Right Command only** for Korean/English switching

The redesign must remove drift between implementation, docs, debugging history, and future work planning.

---

## 2. Product Requirements

### R1. Trigger ownership

- The app supports **Right Command only** as the IME trigger.
- Right Option is not supported.
- Any UI, setting, or code path that presents Right Option as a supported trigger must be removed or marked legacy during migration.

### R2. Context-aware transport

- The app must select switching transport by runtime context.
- At minimum the design must handle these contexts:
  - local macOS
  - Windows VDI
  - remote Mac / screen sharing
  - terminal-like environments such as Claude Code

### R3. Caps Lock ownership

- Caps Lock remains system-owned by default.
- The app must not depend on Caps Lock for the IME trigger path.
- The app must not claim Caps Lock relay behavior unless code, docs, and tests all confirm it.

### R4. Stabilization

The redesign must explicitly manage the known post-switch failure family:

- first-character loss
- composing-text corruption
- replay timing issues
- VDI ghost shortcuts
- terminal/CLI garbage text after switching

### R5. Documentation integrity

- User-facing docs and developer-facing docs must describe only verified behavior.
- Unknown contexts must be tagged as `verification required`.
- Any user-visible behavior change must update docs in the same change.

---

## 3. Known Problem Set

### P1. Trigger model drift

- Spec direction is Right Command only.
- Historical code/UI exposed Right Option as an alternate trigger.
- The redesign must keep that support removed.

### P2. Caps Lock drift

- Current code avoids handling Caps Lock.
- Historical docs implied `Caps Lock -> F19` behavior.
- The redesign must keep user-facing docs aligned with Caps Lock system ownership.

### P3. Screen-sharing uncertainty

- Remote Mac / screen-sharing behavior is not yet validated as a first-class runtime context.

### P4. Terminal / Claude Code instability

- Current evidence shows Right Command can produce unexpected terminal text in Claude Code.

### P5. Existing repo workflow gaps

- No active git hooks
- No lint tool configured
- No formatter configured
- No test target configured
- Only release CI exists today

---

## 4. Scope

### In scope

- Right Command-only trigger redesign
- context model definition
- transport model definition
- stabilization model definition
- documentation split and cleanup
- task planning rules
- TDD / Git hook / commit gate rules
- debugging and log filtering rules

### Out of scope

- Right Option feature retention
- app-owned Caps Lock switching
- unverified F19 relay claims
- broad UI redesign unrelated to trigger stability
- arbitrary new trigger customization before core stability is complete

---

## 5. Context Acceptance Criteria

## Local macOS

- Right Command triggers clean input-source switching.
- No stray characters are inserted into normal text fields.
- First character after switching does not drop or enter in the wrong language.

## Windows VDI

- Right Command switches through the F16 relay path.
- Fast switching does not create ghost shortcuts such as `Win+P`.
- Required external dependency is documented clearly: VDI client must map `F16 -> Right Alt`.

## Remote Mac / Screen Sharing

- The behavior is either verified and documented, or marked open.
- No document may imply this path is solved without direct validation.

## Terminal / Claude Code

- Right Command must not emit stray characters, prompt pollution, or escape-like fragments.
- The context remains open until explicitly revalidated.

## Caps Lock

- Caps Lock remains outside the app-owned IME trigger path.
- Docs describe system-owned behavior consistently.

---

## 6. Non-Functional Requirements

### NFR1. Minimal ambiguity

- Each design decision must be tied to a specific context and failure mode.

### NFR2. Tool-agnostic execution

- The docs must be usable by humans or coding tools without extra explanation.

### NFR3. Safety

- Remap changes must include rollback/reset guidance.
- Live keyboard behavior changes require explicit validation notes.

### NFR4. Traceability

- When a bug is fixed, the change must record:
  - context
  - trigger path
  - transport path
  - stabilization rule touched

---

## 7. Exit Conditions For This Design Phase

- Split design docs exist and are internally consistent.
- A task system exists with AC and commit checkpoints.
- Development workflow rules exist for TDD, hooks, docs, and verification.
- Debugging rules exist, including log filtering script requirements.
- The design set can be used as the source of truth for implementation.

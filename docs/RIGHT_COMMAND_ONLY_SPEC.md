# Right Command Only Input Switching Spec

## Decision Summary

- The app will support **Right Command only** as the Korean/English switch trigger.
- **Right Option support is removed** from the product direction, UI, docs, and implementation plan.
- **Caps Lock is system-owned by default**. The app must not redefine Caps Lock unless a future, separately approved design says otherwise.
- The app remains **context-aware**:
  - Local macOS / remote Mac: use system input-source switching through `Control+Space`.
  - Windows VDI: use `F16` relay passthrough for client-side `Right Alt` mapping.
- Any future work must follow this document before updating code or user-facing docs.

---

## Purpose

This document is the source of truth for the next cleanup and stabilization phase of WinMac Key.

It exists to prevent repeated drift between:

- actual runtime behavior
- historical debugging knowledge
- user-facing documentation
- future implementation work by humans or AI tools

---

## Current Facts Observed In Repo

### Runtime intent

- The current architecture remaps the trigger key to `F16` at the HID layer.
- In local macOS contexts, the app uses `Control+Space` synthesis for input-source switching.
- In Windows VDI contexts, `F16` is passed through so the VDI client can map it to `Right Alt`.

### Caps Lock

- Current code explicitly avoids handling Caps Lock.
- Current code removes Caps Lock mappings from app-managed remap tables.
- Current code comments state that Caps Lock is delegated to the system.

### Documentation drift history

- Earlier docs and in-app help text described or implied `Caps Lock -> F19 -> Caps Lock` relay behavior in VDI.
- That behavior was not a verified implementation fact and has now been removed from current user-facing docs.
- Future work must not reintroduce those claims without code and runtime proof.

### Historical evolution

- The project moved from direct input-source switching (`TISSelectInputSource`) to `Control+Space` synthesis.
- The project later moved to HID relay keys (`F18`, then `F16`) to avoid modifier contamination in VDI.
- Buffering, verification, and replay logic were added to reduce:
  - first-character loss
  - composing-text corruption
  - VDI ghost shortcuts such as `Win+P`

---

## Problem History

The app was shaped by repeated debugging across multiple contexts:

1. The original goal was to switch Korean/English with a Mac-side modifier that feels natural for Windows users.
2. Karabiner, Hammerspoon, and similar tools did not provide consistent cross-context behavior.
3. Local macOS behavior was achievable, but reliability degraded in remote and VDI environments.
4. Remote Mac / screen-sharing paths introduced cases where switching failed or produced unexpected text behavior.
5. Some terminal-like environments, including Claude Code usage, exposed odd string/input results after switching.
6. At least one current Claude Code reproduction shows Right Command producing unexpected terminal text instead of a clean switch result. This is active evidence, not just historical memory.
7. VDI contexts produced ghost shortcut bugs after fast switching, including Windows shortcut misfires.
8. First-character loss after switching remained a repeated issue.
9. Caps Lock behavior became confused because system behavior, app behavior, and stale docs drifted apart.

This spec is intended to stop further drift and simplify the model.

---

## Scope

This spec covers:

- trigger key ownership
- transport selection by context
- post-switch stabilization rules
- documentation cleanup requirements
- implementation order for future work

This spec does **not** claim that every listed context is already solved.

---

## Explicit Decisions

### 1. Trigger policy

- Supported trigger: **Right Command only**
- Removed trigger: **Right Option**

Implications:

- user settings must no longer present Right Option as a supported toggle trigger
- docs must no longer describe Right Option as a first-class path
- implementation must remove Right Option branching where it only exists to support trigger choice

### 2. Caps Lock policy

- Caps Lock is **not** an app-owned switch key.
- Caps Lock remains a **system-owned key** unless a future design explicitly changes that.
- The app must not present Caps Lock relay behavior as implemented unless code and tests prove it.

### 3. Context policy

The app is not “one trigger, one transport” anymore.

The model is:

`Right Command trigger -> context resolution -> transport execution -> verification/stabilization`

### 4. Documentation policy

- Docs must describe only verified current behavior.
- Historical experiments and possible workarounds must not be presented as current product behavior.
- Unknown or unverified cases must be marked `verification required`.

---

## Architecture Principles

### Principle A — Trigger ownership is simple

There is exactly one app-owned IME trigger:

- `Right Command`

This reduces UI complexity, docs complexity, and debugging branches.

### Principle B — Context decides transport

The trigger does not directly decide the switching mechanism.

Instead:

1. detect context
2. choose transport
3. execute transport
4. stabilize post-switch input

### Principle C — Stabilization is part of the architecture

The following are one problem family and must be treated as such:

- first-character loss
- composing text corruption
- duplicate or early replay
- VDI ghost modifier shortcuts
- terminal/CLI odd string behavior after switching

They are not separate one-off bugs.

### Principle D — Caps Lock stays out of the critical path

The IME trigger path must not depend on Caps Lock behavior.

---

## Behavior Matrix

| Context | Trigger | Transport | Expected Result | Verification State |
|---|---|---|---|---|
| Local macOS | Right Command | `Control+Space` synthesis | macOS input source switches cleanly | current design target |
| Windows VDI | Right Command | `F16` passthrough -> VDI client maps to `Right Alt` | Windows Han/Eng switch works without modifier contamination | current design target |
| Remote Mac / Screen Sharing | Right Command | `verification required` | should match local-Mac user intent, but transport must be revalidated | unknown |
| Terminal / Claude Code | Right Command | F16 suppress trigger + terminal direct input-source switch | must not emit stray characters, escape-like fragments, or prompt pollution during switching, and must not leak real Command shortcuts | mitigation added, runtime verification required |
| Caps Lock | system-owned | none by default | behaves according to macOS / VDI / client system rules, not app rules | current design target |

Notes:

- Remote Mac / Screen Sharing is not declared solved in this spec.
- Terminal / Claude Code behavior is not declared solved in this spec.
- Any claim about that path must be supported by direct reproduction and updated docs.

Terminal-specific warning:

- If a terminal-path design allows the focused app to still observe bare Right Command as a real Command modifier, that design is invalid even if input-source switching also occurs.

---

## Non-Goals

The following are out of scope for this phase:

- supporting Right Option as an alternate trigger
- making Caps Lock an app-owned IME switch key
- claiming `Caps Lock -> F19` relay as a current feature without proof
- adding more configurable trigger permutations before the core path is stable
- broad UI expansion before behavior contracts are clean

---

## Required Product Cleanup

### A. UI and settings cleanup

- remove Right Option trigger selection from settings and app state
- remove text that suggests multiple supported trigger keys unless the text is strictly historical

### B. Docs cleanup

Update all user-facing docs to reflect:

- Right Command only
- Caps Lock is system-owned
- local macOS uses `Control+Space`
- VDI uses `F16 -> Right Alt`
- remote Mac / screen-sharing behavior is under verification if not proven

### C. Drift cleanup

Remove or rewrite any text that implies:

- current supported Right Option trigger behavior
- current supported `Caps Lock -> F19` relay behavior
- unsupported certainty for remote/screen-sharing contexts

---

## Migration Tasks

### Phase 1 — Source-of-truth alignment

1. Add this spec to the repo.
2. Add or update a behavior matrix document if needed.
3. Rewrite stale user docs and in-app help to match this spec.

### Phase 2 — Trigger simplification

1. Remove Right Option trigger selection from state and settings.
2. Remove Right Option trigger references from menus, help, and README.
3. Ensure the trigger pipeline is expressed as Right Command only.

### Phase 3 — Context revalidation

1. Re-test local macOS switching.
2. Re-test Windows VDI switching and ghost shortcut prevention.
3. Re-test remote Mac / screen-sharing behavior.
4. Re-test terminal/CLI environments including Claude Code usage.

### Phase 4 — Stabilization tuning

1. Validate input-source change verification timing.
2. Validate replay minimum hold behavior.
3. Validate VDI relay cooldown behavior.
4. Tune only after measured reproductions exist.

---

## Acceptance Criteria

The cleanup phase is complete only if all of the following are true.

### Trigger and ownership

- Right Command is the only supported IME trigger in code, UI, and docs.
- Right Option is no longer exposed as a supported trigger.
- Caps Lock is described consistently as system-owned.

### Documentation

- README, setup docs, VDI docs, in-app help, and doctor text agree with this spec.
- No user-facing text claims unverified `F19` relay behavior as a current feature.

### Local macOS behavior

- Right Command switching works with current `Control+Space` architecture.
- first-character behavior is revalidated against current buffering rules.

### VDI behavior

- Right Command switching works through `F16 -> Right Alt` mapping.
- fast switching does not reintroduce known ghost shortcut issues.

### Unknown contexts

- Remote Mac / screen-sharing behavior is either:
  - verified and documented, or
  - explicitly listed as still open
- Terminal / Claude Code behavior is either:
  - verified to switch cleanly without terminal garbage text, or
  - explicitly listed as still open

---

## Risk List

### Risk 1 — stale doc assumptions

Old docs may continue to reintroduce false expectations around Right Option or F19.

### Risk 2 — hidden trigger branches

Right Option support may still exist indirectly in state, settings, logs, or migration text.

### Risk 3 — screen-sharing path remains under-specified

If remote Mac behavior is not tested separately, local assumptions may be wrong.

### Risk 4 — terminal-like environments remain fragile

Claude Code or similar environments may expose switching/replay issues not visible in standard text fields.

### Risk 5 — regression during simplification

Removing Right Option support may uncover code paths that silently depended on trigger configurability.

---

## Implementation Order

1. **Document truth first**
   - keep this file as the root spec
   - align README, setup docs, VDI docs, help, and doctor text

2. **Remove Right Option from product surface**
   - settings
   - app state
   - help text
   - menu text

3. **Audit code for hidden trigger branching**
   - trigger selection
   - logs
   - migration copy
   - diagnostics

4. **Revalidate local and VDI behavior after simplification**
   - local text entry
   - VDI Han/Eng switching
   - VDI fast-switch ghost shortcuts

5. **Run focused validation for unsolved contexts**
   - screen sharing
   - Claude Code / terminal-like environments

6. **Only then tune stabilization**
   - do not retune timing until the trigger model and docs are simplified

---

## Working Rule For Future Tools

Any human or AI tool working on this repo must follow these rules:

1. Do not add Right Option support back unless a new approved design replaces this spec.
2. Do not treat Caps Lock as app-owned unless a new approved design replaces this spec.
3. Do not claim `F19` relay as implemented without direct code and runtime proof.
4. When behavior differs by context, update the behavior matrix before or with code changes.
5. When a bug is fixed, record:
   - affected context
   - trigger path
   - transport path
   - stabilization rule changed

This file is the reference point for future implementation work.

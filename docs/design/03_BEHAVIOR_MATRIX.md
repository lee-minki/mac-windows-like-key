# Behavior Matrix

## 1. Purpose

Use this file as the runtime contract by context and scenario.

If code changes behavior, update this file in the same change.

---

## 2. Context Matrix

| Context | Trigger | Transport | Expected Behavior | Current Status |
|---|---|---|---|---|
| Local macOS | Right Command | Control+Space synthesis | clean input-source switch with no stray text | target |
| Windows VDI | Right Command | F16 passthrough -> Right Alt | clean Han/Eng switch with no ghost shortcut | target |
| Remote Mac / Screen Sharing | Right Command | verification required | match intended local behavior or document exception | open |
| Terminal / Codex / Claude Code | Right Command | F16 suppress trigger + terminal direct input-source switch + short terminal settle replay | no prompt pollution, no stray characters, no live Command shortcut leakage, no Ghostty paste overlay | mitigation added, runtime verification required |
| Caps Lock | system-owned | none | not used as app trigger | target |
| Bound keyboards | device-scoped `hidutil --matching` | simultaneous per-device layers | built-in and external layouts stay correct when alternating input | implemented, runtime verification pending |
| Horizon focus change | all bound profiles | local/VDI desired keys reapplied together | every keyboard uses Windows layout in VDI and Mac layout outside | implemented, runtime verification pending |

---

## 3. Scenario Matrix

| Scenario ID | Scenario | Context | Pass Condition | Status |
|---|---|---|---|---|
| S1 | switch in normal macOS text field | Local macOS | language changes cleanly | pending verification |
| S2 | type first character immediately after switch | Local macOS | first character is not dropped or mis-languaged | pending verification |
| S3 | fast switching with Shift+letter | Local macOS | no weird mixed input | pending verification |
| S4 | switch in Windows VDI | Windows VDI | Right Alt path works through client mapping | pending verification |
| S5 | switch then type immediately in VDI | Windows VDI | no Win+P / ghost shortcut | pending verification |
| S6 | switch in remote Mac screen-sharing session | Remote Mac / Screen Sharing | result documented with evidence | open |
| S7 | switch inside Codex or Claude Code prompt | Terminal / Codex / Claude Code | no stray prompt text, no paste overlay, no first-character romanization after fast switch, and no Command shortcut leakage | user-verified on Ghostty / broader verification pending |
| S8 | press Caps Lock | Any | app does not claim ownership | pending verification |
| S9 | alternate one key at a time between built-in and Keys-To-Go 2 | Local macOS | each first key uses its own bound profile | pending verification |
| S10 | enter and leave Horizon with both keyboards connected | Windows VDI / Local macOS | both device layers switch context together; F16 relay remains present | pending verification |
| S11 | reconnect Keys-To-Go 2 while engine is on | Local macOS | `046D:B38C` device layer is reapplied before normal use | pending verification |

---

## 4. Failure Catalog

### F1. First-character loss

- signature: `wㅏ전거`, `xㅓ미널`, or equivalent mixed first character
- likely area: verification and replay timing

### F2. VDI ghost shortcut

- signature: `Win+P`, `Win+Shift+R`, or similar shortcut misfire
- likely area: modifier contamination or relay timing

### F3. Terminal garbage text

- signature: prompt pollution, stray characters, escape-like fragments in terminal-like UI
- known reproduction target: Codex desktop / Claude Code

### F3b. Terminal command shortcut leakage

- signature: search focus, Spotlight-like behavior, `Cmd+N`, `Cmd+D`, or other live Command shortcut behavior after Right Command tap
- known reproduction target: Ghostty terminal context
- likely area: bare Right Command `flagsChanged` visible to the app

### F4. Screen-sharing mismatch

- signature: behavior differs from local Mac assumptions
- likely area: context detection or transport mismatch

### F5. Caps Lock misunderstanding

- signature: docs imply ownership that code does not implement
- likely area: stale docs and help text

---

## 5. Verification Evidence Format

Each scenario verification record must include:

- context
- app/window under test
- trigger used
- expected behavior
- actual behavior
- pass/fail
- log snippet or screenshot reference if failure occurs

Template:

```text
Scenario: S7
Context: Terminal / Codex / Claude Code
Trigger: Right Command
Expected: no stray prompt text
Actual: [paste exact text or screenshot ref]
Result: FAIL
Evidence: [log file / screenshot / reproduction steps]
```

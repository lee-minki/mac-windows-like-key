# Regression Notes

## 1. Purpose

This file records behavior regressions that must not be reintroduced.

Use it before changing trigger detection, transport selection, event suppression, or terminal handling.

---

## 2. Ghostty / Claude Code Terminal Regression

### Symptom

In `Ghostty` while running Claude Code, Right Command regression symptoms included:

- switching felt slower than before
- bare Right Command could open search-like UI
- Ghostty shortcuts such as `Cmd+N` or `Cmd+D` could fire
- raw terminal text such as `[57379u` could appear

### Scope

- affected context: terminal-like apps, especially `com.mitchellh.ghostty`
- not the same as Claude Desktop app behavior
- the failure was specific to terminal context handling

### Root Cause

The regression happened when terminal mode changed from the previous boring-key model to a bare-Command tap model.

The broken sequence was:

1. disable HID remap for terminal mode
2. detect Right Command using `flagsChanged`
3. keep using `NSEvent` global monitor
4. allow the real Command modifier to reach the focused terminal app

That combination is unsafe because `NSEvent.addGlobalMonitorForEvents` is observer-only. It can detect the tap, but it cannot suppress the real Command event.

As a result, the terminal app still sees a real Command modifier and may:

- trigger menu accelerators
- trigger app shortcuts
- emit raw terminal keyboard protocol sequences

### Verified Design Lesson

For terminal-like apps, **bare Right Command tap detection without event suppression is a forbidden pattern**.

If the app still receives a real Command modifier, the design is wrong even if input-source switching also happens.

### Follow-up History

The regression was resolved in stages:

1. restoring the boring-key trigger model (`Right Command -> F16`) removed raw F16 text such as `[57379u`
2. removing bare Command tap handling removed search UI and live Command shortcut leakage such as `Cmd+N` and `Cmd+D`
3. Ghostty still showed a transient `pasting text` overlay and slight stutter while typing
4. that remaining issue was addressed by keeping the F16 suppress trigger while switching terminal-like apps via direct input-source selection instead of `Control+Space + buffered replay`
5. user-observed result after this change: the `pasting text` overlay disappeared

Current recorded state:

- `[57379u]` no longer appears
- Command shortcut leakage is no longer observed
- `pasting text` overlay no longer appears
- runtime validation should still continue for typing smoothness and broader terminal coverage

---

## 3. Forbidden Pattern

Do **not** reintroduce this design:

- disable `Right Command -> F16` HID remap
- detect terminal switching via bare `Right Command` `flagsChanged`
- rely on `NSEvent` global monitor to observe that tap
- expect Ghostty/terminal apps not to see real Command shortcuts

Why forbidden:

- `flagsChanged` leaves Command semantics visible to the app
- `NSEvent` global monitor does not suppress
- terminal apps can interpret the modifier for shortcuts or keyboard protocol output

---

## 4. Safe Design Constraint

Terminal-like contexts must satisfy **both** conditions:

1. IME switching works
2. the focused terminal app does **not** observe bare Right Command as a live Command shortcut

If condition 2 fails, the implementation is not acceptable.

---

## 5. Validation Checklist For Future Changes

Before shipping any terminal-related trigger change, verify all of these:

- Right Command does not open search UI
- Right Command does not trigger Ghostty shortcuts
- Right Command does not emit raw text like `[57379u`
- Right Command does not trigger a `pasting text` overlay in Ghostty
- switching latency is not worse than the previous stable path
- logs confirm the intended transport path
- docs are updated with the exact terminal behavior

---

## 6. Commit Gate

Any future commit that changes terminal trigger behavior must include:

- reproduction steps
- pass/fail result in terminal context
- explicit statement of whether the app still sees a real Command modifier
- doc updates in this file and the behavior matrix when behavior changes

# Debugging Guide

## 1. Purpose

Debugging for this repo must preserve tokens, preserve evidence, and avoid repeated free-form searching.

Use structured filtering first.

---

## 2. Debugging Priorities

When a switching issue appears, classify it before changing code.

### Class A — Trigger issue

- Right Command not detected
- wrong trigger still exposed

### Class B — Transport issue

- local macOS switch path fails
- VDI relay path fails
- wrong context gets selected

### Class C — Stabilization issue

- first-character loss
- composing corruption
- VDI ghost shortcuts
- terminal prompt pollution

### Class D — Docs drift

- docs describe behavior not supported by code

---

## 3. Reproduction Record Template

```text
Issue ID:
Context:
App under test:
Trigger:
Expected:
Actual:
Reproduction steps:
Frequency:
Logs captured:
Screenshot/video:
```

---

## 4. Logging Rule

Log output must be filterable by stage.

Preferred tags:

- `TRIGGER`
- `CONTEXT`
- `TRANSPORT`
- `VERIFY`
- `BUFFER`
- `REPLAY`
- `VDI`
- `TERM`

If logs are modified in code later, keep these categories machine-filterable.

---

## 5. Token-Saving Rule

Do not paste full raw logs into chat unless already filtered.

First filter by:

1. time window
2. category
3. trigger event
4. failing context

---

## 6. Log Filtering Script Requirement

The repo should add a shell script under `scripts/` for filtered log extraction.

Required target file:

- `scripts/filter-logs.sh`

Required behavior:

- accept a log file path or stdin
- filter by category keyword
- filter by time substring when available
- support preset modes:
  - `trigger`
  - `vdi`
  - `term`
  - `buffer`
  - `verify`
- emit concise output intended for human debugging or AI context sharing

Example target usage:

```bash
scripts/filter-logs.sh --mode term --since "09:50" app.log
scripts/filter-logs.sh --mode vdi app.log
```

Until the script exists, manual filtering should mimic those modes.

---

## 7. Context-Specific Debug Checklist

### Local macOS

- confirm Right Command trigger path
- confirm `Control+Space` system shortcut configuration
- inspect verify/buffer/replay sequence

### Windows VDI

- confirm context detection
- confirm F16 passthrough path
- confirm client-side `F16 -> Right Alt` mapping
- inspect ghost shortcut symptoms

### Remote Mac / Screen Sharing

- confirm target app/session type
- verify whether local transport assumptions still hold
- record whether behavior differs before changing code

### Terminal / Claude Code

- capture exact prompt pollution text
- capture logs around trigger/verify/replay
- compare against normal text field behavior in the same session
- confirm whether the failed terminal direct-tap experiment was active for the bundle under test
- confirm whether the focused terminal app still observed a real Command shortcut side effect

### Terminal Regression Rule

If a terminal fix introduces any of the following, stop and treat it as a regression:

- search UI opens
- Ghostty shortcut fires
- Spotlight-like behavior appears
- raw terminal text such as `[57379u` appears

That means the terminal app still saw a real Command path.

---

## 8. Debug Exit Rule

Do not call a bug fixed unless all three are true:

1. reproduction exists
2. post-fix result is verified
3. behavior matrix and relevant docs were updated

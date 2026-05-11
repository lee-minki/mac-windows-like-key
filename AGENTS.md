# mac-windows-like-key

Repo-specific instructions. Use `/Users/mk/CLAUDE.md` for global safety and environment rules.

## Overview
- Native macOS menu bar utility for Korean/English input switching.
- Core stack: SwiftUI + MenuBarExtra + CGEventTap + IOHIDManager + `hidutil`.
- Main risk area: keyboard remapping changes can affect live system behavior.

## Read First
1. `README.md` — product behavior and build entrypoint
2. `docs/SETUP_GUIDE.md` — local setup and troubleshooting
3. `docs/VDI_SETUP.md` — Horizon/VDI behavior and relay-key model

## Working Areas
- `WinMacKey/Services/` — event tap, remap, device/profile logic
- `WinMacKey/Views/` — UI and menu bar surfaces
- `WinMacKey/Models/` — state/data models
- `docs/` — setup and VDI user docs

## Commands
```bash
# build debug app
xcodebuild -project WinMacKey.xcodeproj -scheme WinMacKey -configuration Debug -derivedDataPath build/DerivedData build

# open built app
open build/DerivedData/Build/Products/Debug/WinMacKey.app
```

## Source-of-Truth Rules
- Keep local Mac behavior and VDI behavior distinct.
- `docs/SETUP_GUIDE.md` and `docs/VDI_SETUP.md` are the user-facing source of truth for setup; `docs/manual.html` must either mirror them or clearly point back to them.
- Preserve the current F16 relay model. F18 is historical unless explicitly reintroduced with code and runtime evidence.
- Treat device/profile auto switching as behavior-critical.

## Agent Rules
- Any user-visible behavior, setup change, permission change, or workflow change must update docs in the same change.
- Never auto-commit, auto-push, change git config, or force git operations.
- Never automate macOS privacy/security setting changes without user approval.
- Before touching remap logic, understand whether the change affects local macOS, VDI, or both.
- Prefer minimal fixes; this repo is sensitive to regression in live keyboard handling.

## Gotchas
- The app depends on Accessibility/Input-style permissions and real device context; code-only reasoning is not enough for final verification.
- `hidutil` remaps are safety-sensitive. Document rollback/reset steps when changing related behavior.
- VDI behavior depends on external client mapping (`F16 -> Right Alt`) and should not be assumed purely from local code.

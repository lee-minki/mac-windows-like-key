# Next Agent Brief

## Product Semantics

The icon should not primarily mean "Windows plus Mac". The code and docs point to a narrower and stronger meaning:

`Right Command -> F16 relay -> local Mac input-source toggle or VDI pass-through`

For public-facing branding, simplify that to:

`Right Command -> Han/English`

Use F16 only in setup/VDI/manual contexts.

## Code/Docs Anchors

- `README.md:23-24`: user-facing summary of Right Command to F16 and local/VDI split.
- `WinMacKey/WinMacKeyApp.swift:548-554`: Right Command is remapped to F16.
- `WinMacKey/WinMacKeyApp.swift:228-237`: VDI passes F16 through; local Mac suppresses F16 then toggles the input source.
- `docs/FEATURE_SPEC.md:162-170`: keyboard cleaning mode is planned and explicitly unimplemented.
- `docs/private/PRO_TIER_GATING_PLAN.md:15-17`: current Pro boundary is device auto profile switching only.
- `scripts/release.sh:216-234`: current DMG generation has no custom visual layout stage.

## Recommended Work Order

1. Open `prepared/AppIcon_candidate_A.appiconset` in a throwaway Xcode asset catalog or copy into a temporary branch only.
2. Compare candidate A against current icon at 16, 32, 128, 512 px on light/dark Finder backgrounds.
3. If accepted, rebuild a clean 1024 px master with exact symbols. Do not rely on AI-rendered text at small sizes.
4. Capture real app screenshots for Gumroad/manual: menu popover, settings/profile, Doctor/Event Viewer, actual VDI setup if available.
5. Redraw the VDI diagram with controlled text and neutral OS-safe icons.
6. Decide whether keyboard cleaning is Lite, Pro, or future roadmap before using it in paid marketing.

## Risk Notes

- The generated VDI image is too text-heavy for direct production use.
- The generated DMG image contains an App Store-like folder mark; replace it before shipping.
- The generated permission illustration must not substitute for real macOS permission screenshots.
- If cleaning mode becomes Pro, update Pro docs because the current Pro plan says only device auto switching is paid.
- If a DMG background is used, the release script needs Finder layout work; simply adding the PNG to the repo will not affect the mounted DMG.

# Asset Matrix

| File | Intended use | Current quality | Production note |
|---|---|---|---|
| `generated/01_icon_candidate_a_right_command_han_a.png` | Main app icon concept | Strongest semantic fit. Right Command + Han/A is immediately understandable. | Recommended base. Rebuild exact symbols/vector overlay before shipping. |
| `generated/02_icon_candidate_b_f16_relay.png` | Technical app icon or relay explainer | Good for engineering story, less direct for first-time users. | Avoid making F16 the primary brand message. F16 text may be too small at icon sizes. |
| `generated/03_feature_candidate_c_cleaning_mode_pro.png` | Pro/Power Tools card for keyboard cleaning mode | Clean, readable, feature-specific. | Feature is currently planned/unimplemented. Do not present as shipped. |
| `generated/04_installer_dmg_background_concept.png` | DMG drag-to-Applications layout concept | Useful spacing and install flow. | Replace generated App Store-like mark with a controlled Applications/folder icon before production. |
| `generated/05_permission_onboarding_illustration.png` | Permission/onboarding manual illustration | Good abstract explanation of Accessibility/Input Monitoring. | Do not use as a fake System Settings screenshot. Real permission steps need real screenshots. |
| `generated/06_vdi_relay_manual_illustration.png` | VDI relay manual/marketing diagram | Clear flow, but contains generated text and Windows-like UI details. | Use as layout reference only. Redraw labels/icons in controlled vector or HTML/SVG. |
| `prepared/AppIcon_candidate_A.appiconset` | Xcode icon comparison candidate | Standard appiconset sizes generated from candidate A. | Compare only; do not ship without small-size QA. |
| `prepared/AppIcon_candidate_B.appiconset` | Xcode icon comparison candidate | Standard appiconset sizes generated from candidate B. | Compare only; less recommended than A for public icon. |

## Visual Language

- Primary palette: off-white keycap, graphite base, green/cyan relay accent.
- Avoid: Apple logo, official Windows logo, Windows four-pane logo, WMK text, long labels, fake system UI text.
- Prefer: right-positioned `⌘` key, `한/A` or `가/A`, single swap arrow, calm macOS utility feel.

## Generated Sizes

- Square icon/feature images: 1254 x 1254 px originals.
- Manual/installer images: 1586 x 992 px originals.
- Prepared appiconsets: standard 16, 32, 64, 128, 256, 512, 1024 px variants.

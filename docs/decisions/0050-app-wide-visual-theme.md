# 0050 · One app-wide visual theme

Proposal: #50 (accepted by lazy consensus: no objections by the deadline).

## Context
Each lane styled its own screens with stock iOS defaults, so tabs looked like different apps. The new-home lane built a shared theme in `ios/Moove/Shared/Theme.swift` (#47, #76).

## Decision
All screens use the shared theme: cream / warm-black backgrounds, warm ink, sage accent, monospace for headings, labels and numbers, thin ledger rules instead of cards, pill buttons, light and dark mode, text contrast ≥ 4.5:1. Screens opt in with `.mooveScreen()` and use the theme's text styles and components (`PageHeader`, `ListHeader`, `LedgerRow`, `.pill(...)`, `MonoTag`).

## Consequences
- Screens not in open PRs are restyled now (#50 rollout PR).
- Scan, Inventory and Item detail are restyled after the ios-capture lane's open PRs merge, to avoid conflicts.
- New screens should start from the theme components.

## Addendum: per-tab palette and an Appearance setting (#335)
Lisa: "can you make a dark mode button? or even in light mode it feels like each page is too similar".

- **Appearance** (Settings > Appearance: System / Light / Dark, `@AppStorage("moove.appearance")`, `Shared/Appearance.swift`). `MooveApp` applies it once at the root (`.followsAppAppearance()`): `.preferredColorScheme` plus every window's `overrideUserInterfaceStyle`, so sheets, full-screen covers and UIKit views (ARView, share sheets) follow an in-app choice and System really goes back to the system. Settings' toolbar has a small sun/moon button that flips Light/Dark. RealityKit scene backgrounds resolve against SwiftUI's `colorScheme` (`FloorPlan3DView.sceneBackgroundColor(for:)`), not the ARView's trait collection, which is unset before the view is in a window.
- **Each tab has a color** from one palette that sits with cream and walnut (`Theme.Palette`, light / dark):

  | Tab | Palette | accent | text-safe accent / fill | page wash |
  |---|---|---|---|---|
  | Scan | sage | `#8B9A7B` / `#9AAA89` | `#55644A` / `#B2C1A0` (fill `#9AAA89`) | `#EDE9DF` / `#26241D` |
  | Items | ochre | `#B48A3E` / `#CFA45A` | `#7D5B1C` / `#D9B36E` (fill `#CFA45A`) | `#EFE8DB` / `#2A231A` |
  | Sell & Buy | terracotta | `#C4683F` / `#DA845C` | `#93461F` / `#E59A76` (fill `#DA845C`) | `#F0E6DB` / `#2B211A` |
  | Move | dusty teal | `#6F9AA0` / `#82AEB4` | `#3D6A71` / `#9CC3C8` (fill `#82AEB4`) | `#EBE9E1` / `#242421` |
  | Summary | plum | `#9A7B95` / `#B496AE` | `#6B4B66` / `#C8AEC2` (fill `#B496AE`) | `#EEE7E0` / `#282220` |

  `TabGroupView` sets `\.tabPalette`; `.mooveScreen()` (page wash, tint, nav bar), `PageHeader` (a short accent mark over the title), `PillPicker` (selected pill filled), `ChoiceChip` and `.pill(.primary)` read it, and the tab bar takes the selected tab's text-safe accent and wash. Outside the tabs (Settings, sign-in) it is `Palette.standard`, the original cream and sage. For a sticky bar or page that sets its own background, use `Theme.Tab.wash` (a `ShapeStyle` that resolves to the current tab) instead of `Theme.bg`.
- Contrast: `text` / `muted` on every wash ≥ 5.1:1, the text-safe accent on wash and `surface` ≥ 4.7:1, `accentInk` on fill and pressed fill ≥ 5.1:1, in both modes. `danger`, `MonoTag` (SIMULATED) and the fixed paper/receipt colors don't change per tab.

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

## Addendum: shared tokens across the redesigned screens (#335)
By Oct 24, each redesigned screen had its own metaphor (Inventory museum/binder, Review deck and box labels, Shopping storefront, Agents receipts, Listings posters, Pack kraft boxes and truck, New Home room shots). The metaphors stay, but they now share tokens from `Theme.swift`, so the screens feel like one app:
- **Corners** `Theme.Radius`: `tag` 4 (paper labels, stamps, tape, photo mats), `chip` 10, `card` 14, `panel` 20, `hero` 28 (the one hero card on a screen). The old `radiusSmall/Medium/Large` names are aliases.
- **Shadows** `.mooveShadow(.contact | .paper | .lifted)`: paper lying flat, a sheet resting on the page, something lifted off it. No hand-tuned `.shadow(color: .black…)`.
- **Paper** `Theme.Paper`: `cream`, `ink`, `inkMuted`, `rule`, `kraft`, `tape`. Paper metaphors point their palettes at these instead of their own hex (receipts now; Review's sticky notes in the follow-up). Listings posters keep their palette in MooveKit `PosterPalette`, in one place. Pack's label paper stays light in dark mode on purpose.
- **Spacing** `Theme.Space`: `xs 4 · s 8 · m 12 · l 16 · xl 24 · section 40`, with `screenTop` 16 and `gutter` 20.
- **Type**: monospace stays the voice. One serif display face, `.displayTitle(size)`, for display-level section titles (Inventory halls, Shopping categories; applied in the follow-up PR once those screens' open PRs land). Ledger sections keep `ListHeader`. Courier (receipts) and Marker Felt (Review labels) stay inside their metaphors.
- **States**: `EmptyState` (title, what to do, optional action, between rules) for every empty screen or section; `LoadingLine` (tinted spinner + mono line) for loading; `ShowAllButton` / `CollapsedList` cut long lists to their first 5 rows, with "Show all N".
- **Less text**: no lede that repeats a help block, no count shown twice on one screen, and no explanatory line that repeats a tag or header.

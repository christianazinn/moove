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

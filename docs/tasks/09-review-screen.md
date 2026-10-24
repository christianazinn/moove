---
title: Review screen with sentimental flags
lane: ios-capture
depends: 8
tracks: Anthropic, Visa
stretch: false
---

## Goal
A scrollable list of all items grouped by disposition, where the user can change any decision. Possibly sentimental items are surfaced first for the user to decide.

## Context
iOS screen (`ios/Moove/Features/Review/`) subscribed to `items`. Overrides go through a reducer that sets `dispositionSource=user`. #10 makes this live across two devices. See `docs/data-model.md`.

## Scope
- Sections for keep, sell, donate, trash and "Needs you" (sentimental or undecided items).
- Item row: photo, name, estValue, disposition chip, and reason. Tap for details (comps, vision details).
- Change the disposition with a swipe or menu, which calls `setDisposition` (source=user).
- Totals header: expected sale value and number of items to move.

## Tables / reducers touched
`items` (read; `setDisposition` reducer), `comps` (read).

## Acceptance criteria
- [ ] All fixture items render with photos and prices.
- [ ] The "Needs you" section shows sentimental items at the top.
- [ ] Overrides persist and survive an agent re-run.
- [ ] Smooth scrolling with 50+ items.

## Demo fallback
Local MooveKit fixture data if SpacetimeDB is unreachable (debug toggle).

## Notes & gotchas
- Never auto-decide sentimental items. That's a product principle and a good pitch point.
- Showing the reasoning for each auto-decision builds trust (Visa "Trust & Responsibility", Anthropic "where it could go wrong").

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

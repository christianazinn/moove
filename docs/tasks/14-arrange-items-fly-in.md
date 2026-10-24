---
title: Arrange kept items + fly-in animation
lane: ios-newhome
depends: 13, 8
tracks: Anthropic
stretch: false
---

## Goal
Kept (and bought) items are auto-arranged in the new home, with several layout options. The demo's wow moment: items fly out of the old room and land in the new house.

## Context
The layout solver lives in MooveKit (pure Swift, testable on Linux). Rendering and animation are RealityKit in `ios/Moove/Features/NewHome/`. Inputs: `items` with disposition=keep (and purchased `shoppingList` items) plus the `newHome` floor plan. Saved to `layouts`. See `docs/data-model.md`.

## Scope
- MooveKit `LayoutSolver`: assign items to rooms by category (bed -> bedroom), place them along walls without overlaps or door blocking, and produce 2-3 variants (e.g. compact, open, by function).
- Optional: Claude suggests a room assignment and style rationale, which the solver then validates.
- RealityKit: items as boxes sized to their dims (or the USDZ geometry from the scan if it's feasible), and a layout picker.
- Fly-in animation: the old room's items lift, fly along arcs and settle into their new positions, staggered.
- Save the chosen layout to `layouts`.

## Tables / reducers touched
`items` (read), `newHome` (read), `layouts`, `shoppingList` (read).

## Acceptance criteria
- [ ] At least 2 distinct layouts with no overlapping items (unit tests in MooveKit).
- [ ] The fly-in plays smoothly on the demo phone (aim for 60fps with about 20 items).
- [ ] Switching layouts animates the items to their new positions.

## Demo fallback
Pre-computed layouts from fixtures; the animation still plays.

## Notes & gotchas
- Get the animation looking great before making the solver smart. It's the moment judges remember.
- RoomPlan's object transforms give the original positions for the fly-in start points.
- RealityKit animation APIs: verify against current Apple docs (iOS 17/18).

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

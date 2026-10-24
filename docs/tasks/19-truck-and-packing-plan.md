---
title: Truck and packing plan
lane: ios-newhome
depends: 4, 8
tracks: none
stretch: true
---

## Goal
From the kept items' volume, Moove estimates how many trucks are needed and what movers will cost, and produces a packing plan of which items go in which box.

## Context
Pure algorithms in MooveKit (testable on Linux), with UI in `ios/Moove/Features/Logistics/`. Inputs are the keep items' dims, fragile flag and room. Getting quotes from movers is a known pain point. See `docs/data-model.md`.

## Scope
- MooveKit `VolumeEstimator`: total cubic meters with a packing-inefficiency factor, then a truck count (common truck sizes), then a mover cost estimate (hours times rate, a simple model).
- MooveKit `PackingPlanner`: assign small items to standard box sizes (bin packing heuristic), keep fragile items together, and group by origin room.
- UI: truck recommendation card, cost range, and a box list with contents and labels.

## Tables / reducers touched
`items` (read). Optional `boxes` table if persisted (coordinate with #2).

## Acceptance criteria
- [ ] Unit tests: the estimator and planner give sane outputs on the fixture inventory.
- [ ] No box mixes fragile and heavy items. Boxes are grouped by room.
- [ ] UI shows the truck count, cost range and box list.

## Demo fallback
Precomputed plan from fixtures.

## Notes & gotchas
- Large furniture (bed, sofa) counts toward truck volume but not boxes.
- Stretch: a voice agent that calls movers for quotes (Cartesia) or an agent that books movers with x402. Only if everything else is done.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

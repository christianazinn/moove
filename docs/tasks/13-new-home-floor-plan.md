---
title: New home floor plan
lane: ios-newhome
depends: none
tracks: none
stretch: false
---

## Goal
The user picks their new home and sees its floor plan in 3D with room dimensions. Start with a hardcoded demo house.

## Context
iOS (`ios/Moove/Features/NewHome/`) plus MooveKit models. The data lives in the `newHome` table. Zillow import (Apify Zillow scraper -> floor plan image -> Claude vision -> room polygons) is the riskiest task and comes only if time allows. See `docs/architecture.md`.

## Scope
- MooveKit: `FloorPlan` model (rooms as polygons in meters, doors, windows).
- Hardcoded demo house JSON in `ios/Moove/Resources/demo-house.json` (2-3 bedrooms, living room, kitchen).
- RealityKit view that extrudes walls from the floor plan, with orbit and zoom.
- Manual entry: type in room dimensions (a rectangle per room).
- Stretch: a Zillow URL field that calls a worker endpoint (Apify Zillow scraper + Claude vision) and returns a `FloorPlan`.

## Tables / reducers touched
`newHome` (floorPlan JSON, source=demo|manual|zillow).

## Acceptance criteria
- [ ] The demo house renders in 3D with labeled rooms.
- [ ] Manual room entry produces a renderable plan.
- [ ] The floor plan is saved to `newHome` and loads on relaunch.

## Demo fallback
The hardcoded demo house is the fallback.

## Notes & gotchas
- Keep the coordinate system consistent with RoomPlan (meters, Y-up) so #14 can place scanned items directly.
- Zillow has no public API, and floor plan images aren't on every listing. Apify Zillow actors: verify against the current Apify Store.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

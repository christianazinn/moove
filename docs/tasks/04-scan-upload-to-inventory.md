---
title: Scan upload -> item inventory
lane: ios-capture
depends: 2, 3
tracks: Spacetime
stretch: false
---

## Goal
After a scan, every detected object appears as an item in the user's inventory, with dimensions and a photo, live in SpacetimeDB.

## Context
The iOS app captures the scan and uploads the USDZ and photos to the agent worker's upload endpoint (SpacetimeDB is not a blob store). It then calls reducers to create the `rooms`, `scans` and `items` rows. The worker picks up new items for #5 (vision) and #6 (pricing). See `docs/architecture.md` and `docs/data-model.md`.

## Scope
- `ios/Moove/Features/Scan/`: polished scan flow, then a per-object photo capture prompt, then an upload progress view.
- Upload files to `agents` `POST /upload`, which returns URLs. Coordinate the endpoint with the lane owner or implement a minimal version in `agents/src/upload.ts`.
- Call the `import_scan` reducer once (room name, home, usdz/json URLs, objects with scanObjectId, category, dims, photoUrl). It creates the room, scan and items atomically. Use `create_scan` to re-scan an existing room.
- Inventory list screen in `ios/Moove/Features/Inventory/` subscribed to `items`.

## Tables / reducers touched
`rooms`, `scans`, `items`.

## Acceptance criteria
- [ ] Scan, then photo each object, then items appear in the inventory list within seconds.
- [ ] Item rows have dims and at least one photo URL that loads.
- [ ] Works from the #3 fixture as well (a "load demo scan" debug button).

## Demo fallback
The "Load demo scan" button imports the #3 fixture through the same reducers.

## Notes & gotchas
- Swift SpacetimeDB client: community `ekscrypto/spacetimedb-swift-sdk`, which is risky. If the spike fails, call the worker gateway (REST/WebSocket) instead. See #10.
- Map RoomPlan object UUIDs to `scanObjectId` so the 3D view (#14) can find each item's geometry.
- Upload photos as JPEG at about 1600px max to keep vision calls cheap.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

---
title: Record the demo room scan
lane: ios-capture
depends: none
tracks: none
stretch: false
---

## Goal
Capture one real RoomPlan scan of a furnished room early, and commit its exported data so every lane has realistic test data.

## Context
RoomPlan runs only in the iOS app (`ios/`). Its output (`CapturedRoom` JSON plus a USDZ model) becomes fixtures used by #2 (seed), #4 (upload pipeline), #6 (pricing), #13 and #14 (3D). See `docs/architecture.md`.

## Scope
- Minimal RoomPlan capture view (`RoomCaptureView`) in `ios/Moove/Features/Scan/`. It can be rough; #4 polishes it.
- Export `CapturedRoom` as JSON (Codable) and USDZ (`export(to:)`).
- Take a photo of each detected object (at least 10 objects) for #5.
- Commit to `agents/fixtures/demo-room/` (`room.json`, `room.usdz`, `photos/`). Keep it small and compress photos.

## Tables / reducers touched
None directly. These are fixtures that #2's seed script loads into `rooms`, `scans` and `items`.

## Acceptance criteria
- [ ] Fixture JSON lists at least 10 objects with categories and dimensions.
- [ ] The USDZ opens in Quick Look or Reality Composer.
- [ ] The photos map to object ids (filename = object UUID).
- [ ] Committed by Fri night, and the team is told where it lives.

## Demo fallback
This is itself the fallback for a live scan failing on stage. Keep a second scan of the hotel room as a backup.

## Notes & gotchas
- RoomPlan requires a **physical LiDAR iPhone** (12 Pro or later). It doesn't work in the Simulator.
- Choose a room with varied furniture (chair, desk, bed, lamp, shelves) so sorting and pricing are interesting.
- RoomPlan's `CapturedRoom.Object` categories are coarse (table, chair, sofa, bed, storage...). Photos supply the detail.
- Watch the file sizes: keep the USDZ under ~20 MB, otherwise use Git LFS or an external link.

## Definition of done
Merged to `main` via PR with green CI, issue closed, and `docs/data-model.md` updated if the contract changed.

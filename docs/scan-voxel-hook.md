# Scan → voxel dollhouse hook (#81)

Shows the user's real scanned room (walls, doors, windows, each object's real
position and rotation) in the new-home lane's voxel dollhouse
(`ScanResultsView` / `FloorPlan3DView`) instead of today's estimated
single-rectangle layout.

## What's here

`ios/Moove/Features/Room/RoomGeometry+Dollhouse.swift` (new file, pure math, no
RoomPlan/RealityKit imports; it could move into MooveKit to get `swift test` coverage):

```swift
extension RoomGeometry {
    func dollhousePlan(roomName: String) -> FloorPlan
    func dollhousePlacements(items: [Item], roomName: String = "Room") -> [Placement]
    func dollhouse(roomName: String, items: [Item]) -> (plan: FloorPlan, placements: [Placement])
}
enum DollhouseTransform { ... }   // the world → plan math, with worked examples in comments
```

- **Plan:** one room. The polygon comes from chaining the walls into a loop, with corners
  where consecutive wall lines intersect. If the walls don't close, it uses RoomPlan's
  floor outline, then a convex hull. The room is first rotated so the dominant wall
  direction lies on the plan x axis (walls within 5° of an axis become exactly
  axis-aligned), then shifted so its min corner is at (0, 0). Doors and open passages go
  in `doors`, windows in `windows`. Each one is projected onto its nearest polygon edge.
  `wallHeightM` is the median wall height.
- **Placements:** one per item whose `scanObjectId` equals a scanned object's id
  (`CapturedRoom.Object.identifier.uuidString`, set in `ScanSession.submit`, or
  `"demo-<id>"` for the demo room). Centers use the same transform as the plan.
  `rotationDeg` is the object's yaw plus the room's alignment rotation, converted to
  degrees and snapped to the nearest 90° when it's within 10°. Items that don't match
  (added by photo, or from another scan) are skipped.
- **Pass the same `roomName` to both calls** (or use `dollhouse(roomName:items:)`), because
  `Placement.room` has to match `FloorPlanRoom.name`.

### Rotation convention

Both sides use a right-handed rotation about +Y on world (x, z) = plan (x, y). Rotating by θ
sends local +z to (sin θ, cos θ). That is Rio's `RoomTransform.yaw` and our
`Placement.rotationDeg` (`LayoutSolver.rotationDeg(facing:)`, the quaternion in
`FurnitureLayer`). So `rotationDeg = degrees(yaw + φ)`, where φ is the room's alignment
rotation.

Voxel pieces face local +z. Apple's docs don't say which way a `CapturedRoom.Object`
faces. We assume +z, which matches Rio's demo room (the bed's foot points +z). A wall check
covers the cases where that's wrong: if a piece's front is within 30 cm of a wall and its
back has more than 60 cm of floor, it's turned 180°. The footprint is correct either way
(width is local x, depth is local z), so only the facing can be wrong. If a device scan
shows RoomPlan fronts are −z, set `DollhouseTransform.objectFrontOffsetDeg = 180`.

Checked off-device with a scratch harness (Rio's `RoomGeometry` and the code above, with stub
plan types). It ran on the demo room as-is, and again after rotating it 30°, translating it
and making every wall 7 cm too long. Both gave the same 4 × 3.5 m polygon at (0, 0), the door at
(0.58–1.43, 3.5), the window on x = 4, the same item centers, and rotations of 0/90/180/270.

## What ScanResultsView needs (new-home lane, PR for #76)

Proposed overload:

```swift
init(room: Room?, items: [Item], comps: [Comp],
     plan: FloorPlan, placements: [Placement],
     onSelect: @escaping (Item) -> Void = { _ in })
```

- Store an optional `scanned: (plan: FloorPlan, placements: [Placement])`. When it's set,
  skip `EstimatedRoom.build` and give `FloorPlan3DView` the scanned plan and placements.
- Items without a placement still need spots. `LayoutSolver.solve` can't take pre-placed
  obstacles today, so add something like
  `solve(_ items:, style:, around fixed: [Placement]) -> LayoutOption`. The fixed items
  become `OrientedRect` obstacles, sized from their `LayoutItem` dimensions.
- Caption: show the plan's real `widthM × depthM`. Only show "Layout estimated…" when some
  items were estimated, e.g. "3 of 12 placed by estimate".

## What Rio's side needs (one call site)

Nothing is wired yet, because `ScanResultsView` isn't on this branch. Once both PRs are in,
the call on the Scan page (in `ScanFlowView`'s `.finished` state, or the room screen) is:

```swift
let roomItems = store.items.filter { $0.roomId == room.id }
if let geometry = session.geometry {               // or: try await RoomGeometryLoader.load(room:snapshot:)
    let d = geometry.dollhouse(roomName: room.name, items: roomItems)
    ScanResultsView(room: room, items: roomItems, comps: comps, plan: d.plan, placements: d.placements)
} else {
    ScanResultsView(room: room, items: roomItems, comps: comps)   // estimated layout
}
```

`ScanSession` doesn't keep the new room's id after `importScan`. Look the room up through
the scan whose `capturedRoomJsonUrl` matches the uploaded or local `room.json`, or take the
newest room.

## Limitations

- **One room per scan.** Multi-room captures (several floors) are flattened into one
  polygon. Interior or half walls that don't belong to the outer loop are ignored. Curved
  walls are treated as straight because Rio's `RoomGeometry` doesn't keep `curve`.
- **The plan is 2D.** There's no window sill height or door height. Objects that sit on
  other objects (decor on a dresser, a TV on a stand) get overlapping footprints. The
  voxel side would need to support stacking.
- **The front facing isn't verified on a device.** See above.
- If the item dimensions were edited after the scan, the voxel size differs from the
  scanned footprint, but the center and rotation are still the scanned ones.
- Rotations more than 10° off-axis are kept as they are, e.g. a chair at 37°.
- Only checked with `swiftc -parse` and the scratch harness. It hasn't been built in
  Xcode or with Swift 6.

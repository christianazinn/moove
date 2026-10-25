# iPad scans

Every room scan saved on Lisa's iPad (iPad Pro 11-inch, 2nd gen, LiDAR) during Cal Hacks 13.0, copied off the device as-is from the app's `Documents/scans/` with:

```sh
xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
  --domain-identifier app.moove.Moove.rio --source Documents/scans --destination scans
```

Folder names are the scan's start time (UTC). Five abandoned scans held only an empty `photos/` folder and aren't here.

| Scan | Item photos | Frames | Room photos | Size |
|---|---|---|---|---|
| `2026-10-24T03-55-34` | 0 | 0 | 0 | 64K |
| `2026-10-24T03-57-34` | 2 | 0 | 0 | 736K |
| `2026-10-24T07-05-11` | 3 | 0 | 0 | 484K |
| `2026-10-24T07-07-37` | 15 | 0 | 0 | 2.2M |
| `2026-10-24T08-53-59` | 5 | 0 | 0 | 1.6M |
| `2026-10-24T17-39-03` | 13 | 41 | 4 | 5.9M |
| `2026-10-24T17-56-45` | 11 | 38 | 4 | 6.8M |
| `2026-10-24T19-43-54` | 20 | 41 | 4 | 7.5M |
| `2026-10-24T21-35-31` | 25 | 41 | 4 | 7.7M |
| `2026-10-25T02-01-29` | 18 | 41 | 4 | 5.9M |
| `2026-10-25T02-05-43` | 12 | 19 | 4 | 3.8M |

Each scan folder holds what the app saves (older scans have only some of it):
- `room.usdz`: RoomPlan's parametric 3D model.
- `room.json`: RoomPlan's `CapturedRoom` (walls, doors, windows, openings, objects, with transforms and confidence).
- `geometry.json`: Moove's walls, objects, floors and openings from the scan, as imported.
- `colors.json`: sampled colors per object.
- `photos/`: auto-captured item photos, named by object id.
- `frames/`: keyframes kept during the scan, which multi-frame voting projects the 3D boxes into.
- `room-photos/`: the wide frames sent for the room photo sweep.

The photos have no GPS data. The 120 item photos the recognition eval scores against (`tools/recognition-eval/bench/ipad_truth.tsv`) come from these scans.

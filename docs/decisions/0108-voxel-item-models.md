# 0108 · Voxel models are the only 3D item models

Decision issue: #108 (humans: lisa + rio). Supersedes the photorealistic-model work (#65, #84, #101).

## Context
We had two parallel 3D paths: photorealistic per-item models (Object Capture USDZ, SAM 3D GLBs) and procedural voxel models. Realistic models needed extra capture steps, a GPU worker and large file sync, and mixed badly with the cozy voxel dollhouse.

## Decision
Every item is drawn as a procedural 5 cm voxel model, generated on device from scan and vision data, in every 3D view (scan results, room view, new-home dollhouse, thumbnails). Models must be representative of the real object:
- RoomPlan attributes (chair/sofa/table/storage type) win, then name/material/color/brand words, then scanned dimensions, which set proportions and structure; condition adds wear.
- Seeded randomness only picks small details (grain, book mix, pillow colors), never structure.

Code: `ios/MooveKit/Sources/MooveKit/Voxel/` (VoxelModels, VoxelHouse, VoxelMesher), rendered as one merged mesh per piece (`Features/NewHome/VoxelEntity.swift`).

## Consequences
- Object Capture / SAM 3D / model-URL sync are no longer needed by the app.
- Storing RoomPlan attributes and measured colors on items is proposed in #110.

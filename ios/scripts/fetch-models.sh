#!/bin/sh
# Downloads Core ML models that are too big for git (run by xcodegen's preGenCommand,
# or by hand from ios/). Missing models just turn their feature off, so this never fails
# the build: offline or on CI it skips.
set -u
cd "$(dirname "$0")/.." || exit 0
[ -n "${CI:-}" ] && { echo "fetch-models: CI, skipping"; exit 0; }

fetch() { # <file> <url> <sha256>
  dest="Moove/Resources/Models/$1"
  if [ -f "$dest" ] && [ "$(shasum -a 256 "$dest" | cut -d' ' -f1)" = "$3" ]; then return 0; fi
  mkdir -p Moove/Resources/Models
  echo "fetch-models: downloading $1 (this happens once)"
  if curl -fsSL --retry 2 -o "$dest.part" "$2" && [ "$(shasum -a 256 "$dest.part" | cut -d' ' -f1)" = "$3" ]; then
    mv "$dest.part" "$dest"
  else
    rm -f "$dest.part"
    echo "fetch-models: couldn't get $1; extra object detection (#73) stays off" >&2
  fi
}

# Apple's Core ML YOLOv3 (COCO, 80 classes), int8: detects bikes, suitcases, plants... that RoomPlan doesn't.
fetch YOLOv3Int8LUT.mlmodel \
  https://ml-assets.apple.com/coreml/models/Image/ObjectDetection/YOLOv3/YOLOv3Int8LUT.mlmodel \
  0e32f297ad9cfc0ea8e67276867956488c7ee10dc87c057da4debc939e20b76d
exit 0

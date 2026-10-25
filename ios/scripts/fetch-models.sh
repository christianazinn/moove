#!/bin/sh
# Downloads Core ML models that are too big for git (run by xcodegen's preGenCommand,
# or by hand from ios/). Missing models just turn their feature off, so this never fails
# the build: offline or on CI it skips.
set -u
cd "$(dirname "$0")/.." || exit 0
[ -n "${CI:-}" ] && { echo "fetch-models: CI, skipping"; exit 0; }
models=Moove/Resources/Models

# fetch_zip <name>.mlpackage <url of a zip holding it> <sha256 of the zip> [what stays off without it]
# A stamp file next to the package records the sha it came from, so this runs once.
fetch_zip() {
  dest="$models/$1"
  stamp="$models/.$1.sha256"
  if [ -d "$dest" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$3" ]; then return 0; fi
  mkdir -p "$models"
  echo "fetch-models: downloading $1 (this happens once)"
  tmp="$models/.$1.zip.part"
  if curl -fsSL --retry 2 -o "$tmp" "$2" 2>/dev/null && [ "$(shasum -a 256 "$tmp" | cut -d' ' -f1)" = "$3" ]; then
    rm -rf "$dest"
    if ditto -x -k "$tmp" "$models" && [ -d "$dest" ]; then
      echo "$3" > "$stamp"
    else
      echo "fetch-models: couldn't unpack $1" >&2
    fi
  else
    echo "fetch-models: couldn't get $1; ${4:-extra object detection} stays off" >&2
  fi
  rm -f "$tmp"
}

# Moove's object detector (#82): Ultralytics YOLOE-11L with 127 household classes baked in
# (scooters, bikes, instruments, electronics, appliances, furniture, decor, boxes...).
# Hosted on this repo's `models-v1` prerelease. AGPL-3.0 (Ultralytics).
fetch_zip MooveObjects.mlpackage \
  https://github.com/christianazinn/moove/releases/download/models-v1/MooveObjects-yoloe11l-v1.mlpackage.zip \
  06e4f2dd3fd741aea760b9452274e1108079bd537c284ce5d813ffdc31dbb88d

# Second-stage crop classifier (ObjectRecheck): Meta PE-Core-S/16-384 image tower,
# 8-bit palettized Core ML (~22 MB zip), Apache-2.0. Relabels or rejects the detector's
# finds. Hosted on the `models-v2` prerelease once it's published; until then (or offline)
# the download just fails and the recheck stays off.
fetch_zip ObjectClassifier.mlpackage \
  https://github.com/christianazinn/moove/releases/download/models-v2/ObjectClassifier.mlpackage.zip \
  4365c366ba682263237127f6888681cd8839cbc0be2339faa2bc5920be26140e \
  "the object classifier recheck"

# Replaced by MooveObjects (#82). Remove the old 62 MB COCO model so it isn't bundled.
rm -f "$models/YOLOv3Int8LUT.mlmodel"
exit 0

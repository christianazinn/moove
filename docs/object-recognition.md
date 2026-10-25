# Object recognition: results, test data and how to make it better

This is the state of Moove's object recognition and a guide for whoever works on accuracy next. The scripts are in [`tools/recognition-eval/`](../tools/recognition-eval/README.md).

## How the scan names objects today

1. **RoomPlan** boxes the big furniture (bed, sofa, chair, table, storage, toilet, sink, bathtub, fridge, TV…).
2. **YOLOE-11L** (AGPL-3.0, 127 text prompts baked in, `MooveObjects.mlpackage`) runs on camera frames for the things RoomPlan misses. Its labels map to Moove categories in `ios/MooveKit/Sources/MooveKit/Room/ObjectVocabulary.swift`.
3. **Crop classifier recheck (#381).** Meta **PE-Core-S/16-384** (Apache-2.0) runs as an 8-bit Core ML image tower, `ObjectClassifier.mlpackage` (~23 MB, `models-v2` prerelease, sha256 `4365c366…140e`). A 62-class linear probe sits on top of it (`MooveKit/Resources/ObjectClassifierLabels.*`).
   - Each detector object is classified from its auto photo plus up to 3 tight keyframe crops.
   - `ObjectRecheck` then keeps, relabels, rejects or marks the object `other`.
   - RoomPlan objects can only be rejected, never relabeled.
4. **Server:** Claude vision names each item from its photo. It reports `identifyConfidence` and `closeupHint`, and Google Lens runs on items it isn't sure of. **Reclassify from a photo** (#373) lets the user retake a photo and have vision identify the item again from it.

## Results (Oct 24, 2026)

**Test set:**
- **Public crops:** 1,745 object crops in 45 classes, from Open Images, LVIS and Wikimedia.
- **iPad scans:** 120 real iPad scan photos from 10 scans, labeled by hand: 83 real objects, 30 photos of nothing movable (`none`) and 7 unclear.

The iPad numbers are small (n = 83), so ±1 photo is 1.2 points and the 95% interval is about ±10 points.

### Single-image classifiers

| Method | Public top-1 | iPad top-1 (83) | Non-object rejection on iPad: precision / recall (30) | ms per image (M5 Mac) | Ships on device? |
|---|---|---|---|---|---|
| Recorded scan output (RoomPlan + detector, many frames) | – | 67.5% | – / **0%** | – | yes (before #381) |
| YOLOE-11L detector, one image | 24.8% | 21.7% | 38.5 / 66.7 | 12 | yes |
| Apple `VNClassifyImageRequest` | 38.1% | 37.3% | 69.2 / 30.0 | 5 | built in |
| Apple feature-print kNN (k=5) | 59.5% | 28.9% | 46.7 / 23.3 | 3 | built in |
| CLIP ViT-L/14 zero-shot | 73.8% | 67.5% | 81.2 / 43.3 | 69 | too big |
| **PE-Core-S/16-384 zero-shot** | 76.2% | 62.7% | 89.5 / 56.7 | 17 | **yes** |
| **PE-Core-S + V4 probe + merges + none bias (shipped)** | **82.8%** | 65.1% | 87.5 / 70.0 | 11 (Core ML) | **yes** |
| SigLIP so400m (reference) | 83.2% | 72.3% | 92.0 / 76.7 | 229 | too big |

### What the scan pipeline does with the recheck

Measured on the iPad split, using each object's recorded detector label and its LiDAR size.

| Pipeline | Real objects right (83) | Non-objects rejected: precision / recall (30) | Real objects thrown away |
|---|---|---|---|
| Recorded scan output | 67.5% | 0 / 0 | – |
| **+ PE-Core recheck (#381)** | **78.3%** | **100 / 46.7** | **0** |

- **Fixed 28** (14 real objects relabeled right, 14 non-objects rejected), for example:
  - e-scooter "vacuum" / "shoe rack" → scooter
  - cardboard-box "bins" → box
  - rolling step ladder "vacuum" → ladder
  - radiators "heater", shower curtain "room divider", a light stand "vacuum" → rejected
- **Broke 5:**
  - backpack → table
  - bean bag → backpack
  - laptop → box
  - 2 floor lamps → storage
- **Multi-frame:** using the auto photo plus 3 keyframe crops, with the most confident view winning, reached 80% vs 70% on 70 objects (`research3`). It's suggestive but not significant.

### Per-class accuracy on public crops (%)

| Class | Detector | PE-Core zero-shot | SigLIP so400m |
|---|---|---|---|
| scooter | 58 | 100 | 100 |
| vacuum | 30 | 97 | 100 |
| bicycle | 42 | 95 | 100 |
| lamp | 10 | 88 | 80 |
| toilet / sink / bathtub | 0 / 0 / 0 | 78 / 75 / 82 | 90 / 90 / 92 |
| box | 3 | 52 | 41 |
| ironing board | 0 | 81 | 95 |
| bag | 2 | 20 | 30 |
| table | 18 | 59 | 71 |
| shelf | 18 | 25 | 36 |

The full tables, the top-10 confusions for every method and the 64 hard iPad cases are in `tools/recognition-eval/eval/results.md`.

## Test data: what we used and what to add

### Already used (the internal benchmark)

The benchmark itself isn't in git: about 86 MB, and some images are NC/ND licensed. `tools/recognition-eval/bench/` rebuilds it.

| Source | Licence | What it gave us |
|---|---|---|
| [Open Images V7](https://storage.googleapis.com/openimages/web/index.html) boxes (val/test) | CC BY 4.0 annotations, CC BY 2.0 images | Furniture, appliances, bathroom fixtures, plants, bags |
| [LVIS v1](https://www.lvisdataset.org/) on COCO images | CC BY 4.0 annotations; Flickr per-image licences (some NC/ND) | vacuum, ironing board, stroller, shower curtain, towel rack, radiator, ottoman, dolly |
| [Wikimedia Commons](https://commons.wikimedia.org/) (CC0/PD/CC BY/BY-SA only) | per file | Scooters, upright vacuums, office chairs, rugs, heaters, yoga mats (product-style photos) |
| Our own iPad scans | ours | The 120-photo hard split, labeled in `bench/ipad_truth.tsv` |

### Suggested next datasets to calibrate models (closest to our data first)

1. **[ARKitScenes](https://github.com/apple/ARKitScenes)** (Apple): **iPad Pro LiDAR scans with 3D boxes**, 17 classes (cabinet, fridge, shelf, stove, bed, sink, washer, toilet, bathtub, oven, dishwasher, fireplace, stool, chair, table, tv_monitor, sofa). It's the same sensor and the same kind of frames as ours.
   - **How to use it:** project each 3D box into the low-res frames (`research3/mv_common.py` already does that projection for our own scans) and crop.
   - **Why it matters:** it's the best way to calibrate the **RoomPlan reject threshold** (0.7) on real RoomPlan-style errors.
   - **Licence:** Apple custom; read it before any commercial use. Downloads are per video and often GBs each, so pick about 50 scans.
2. **[ScanNet++](https://kaldir.vc.in.tum.de/scannetpp/) / [ScanNet](http://www.scan-net.org/):** RGB-D indoor scans with many small-object classes. They need a signed agreement and are non-commercial; fine for internal benchmarking.
3. **[SUN RGB-D](https://rgbd.cs.princeton.edu/):** 10k indoor RGB-D images with 2D/3D boxes. One ~6 GB zip; research use.
4. **[Objectron](https://github.com/google-research-datasets/Objectron):** phone videos with 3D boxes for bikes, chairs, laptops, shoes, books, bottles, cameras, cereal boxes and cups. Good for multi-view voting tests. C-UDA licence.
5. **[Objects365](https://www.objects365.org/):** has a **scooter** box class, which the other detection sets lack. Our scooter class is 100% Wikimedia product photos today, which flatters kNN.
6. **More vacuums:** upright, stick and canister. Our vacuum class is mostly robot vacuums.
7. **Our own data (the most valuable):** every **Reclassify from a photo**, **Rename**, **What is it?** and **Not a real item** in the app is a free label on a real scan.
   - Logging `(scan object id, auto photo, detector label, recheck verdict, user's correction)` would grow a real-home test set and a training set for a per-home adapter.
   - Research2 found same-home photos lift accuracy to about 72%.
   - Each object would need an opt-in.

### Metrics to report for any new model

Report every one of these, so models can be compared:
- Top-1 on public crops, overall and macro.
- Top-1 on iPad real objects.
- **Non-object rejection precision and recall** on the iPad `none` photos.
- **Real objects thrown away.** This must stay at 0.
- ms per image on an M-series Mac, plus a device measurement when you can (we haven't measured the A12Z yet).
- Fixes vs breaks against the shipped pipeline, with a sign test.
- Scoring rules from `eval/analyze.py`:
  - fixtures (radiator, shower curtain, towel rack) count as `none`
  - merges: backpack→bag, monitor→television, shelf→storage

## Next steps, roughly by value per effort

1. **Don't apply research5's detector mapping fixes on their own.** Before #381 they took recorded detector objects from 29 to 47 of 84. On top of the shipped recheck (`research6/mapping_with_recheck.md`) they add nothing on iPad scans (79.5% with merges either way):
   - the remaps (`storage bin`/`dollhouse` → box) are already done by the recheck
   - the label drops delete 4 real objects (clothes racks read as crib / sewing machine / room divider, a TV read as air purifier) that the recheck would keep or fix
   - the per-label floors change nothing measurable

   Better targets: things the recheck can't fix, i.e. objects the detector never finds and thin vertical clutter (mop, broom, tripod, dolly) that it calls "vacuum" and the classifier keeps.
2. **Measure on the device.** Time the recheck on an A12Z iPad and a recent iPhone (4 crops per object). Rerun the fused-pipeline numbers on new scans with the full-res keyframes, which research3 couldn't use.
3. **YOLOE-26L.** +2.6 LVIS AP and +6 AP on rare classes at the same size and licence.
   - **Export:** `nms=True`, detection-only (commands in `research` notes: `YOLOE("yoloe-26l.yaml").load("yoloe-26l-seg.pt")`, then `load_prompt_embeddings`, then `export(format="coreml", nms=True, agnostic_nms=True)`).
   - **Needs** the 254 MB `mobileclip2_b.ts`, so do it on a machine with fast internet.
   - **Add negatives:** put wall, door, window, curtain, radiator, plastic sheeting and towel rail in the 33 free prompt slots, mapped to reject.
4. **SigLIP2 ViT-B/16** (Apache-2.0). The 8-bit Core ML image tower already exists ([batmac/ViT-B-16-SigLIP2-Image-CoreML](https://huggingface.co/batmac/ViT-B-16-SigLIP2-Image-CoreML), 93 MB). We didn't benchmark it because downloads were too slow. `text-matrix/make_text_matrix.py` builds its label matrix. Expected between PE-Core-S and SigLIP so400m.
5. **ARKitScenes calibration.** See dataset 1 above; it's what tunes the RoomPlan reject threshold on real RoomPlan errors.
6. **Remaining confusions:** bag vs backpack, table vs storage, shelf vs storage, TV vs monitor.
   - Prompt wording barely helps (`research2`).
   - Height separates table from storage on RoomPlan boxes (0.9 m cut). Detector boxes are too noisy for size priors, except as a veto.
7. **Per-home adapter:** fit the probe on the user's own corrections from earlier rooms of the same home. Research2 found 72% on re-scans of the same rooms; this is unverified on new homes.

## Licences to watch

- Apple **MobileCLIP / MobileCLIP2** weights are research-only, so they can't ship.
- **YOLOE** is AGPL-3.0, which needs a decision before any commercial release.
- PE-Core and SigLIP2 are Apache-2.0.
- Benchmark images carry their sources' licences; some are NC/ND. Keep them internal and don't commit them.

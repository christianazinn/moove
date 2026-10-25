# Moove object classification benchmark

Bench: 1745 public crops (45 fine classes, 40 Moove labels) + 120 iPad scan photos (83 real objects, 30 `none`, 7 `unclear`). Machine: Apple M5, macOS, offline.

Scoring notes: `ceiling fan` == `fan`. On the iPad split a prediction of a fixed fixture (radiator / shower curtain / towel rack) counts as `none`, matching how those were labeled. iPad top-1 excludes `none`/`unclear` rows; none-rejection uses all non-`unclear` iPad rows (positive = truth `none`). kNN public numbers are 5-fold CV grouped by source photo (no crop of the same photo in train and test).

## Summary

| Method | Public top-1 % | Public macro % | iPad top-1 % (n=83) | iPad none-reject precision % | recall % (n=30) | median ms/img |
|---|---|---|---|---|---|---|
| Recorded on-device detector (scan output) | n/a | n/a | 67.5 | 0.0 | 0.0 | n/a |
| Detector (app thresholds) | 24.8 | 22.6 | 21.7 | 38.5 | 66.7 | 12.2 |
| Detector (any score >= 0.15) | 27.4 | 24.8 | 21.7 | 46.7 | 46.7 | 12.2 |
| Detector (app thr., largest-box pick) | 27.6 | 25.0 | 27.7 | 38.5 | 66.7 | 12.2 |
| VNClassify (t=0.02) | 38.1 | 35.0 | 37.3 | 69.2 | 30.0 | 4.6 |
| FeaturePrint kNN k=1 | 54.5 | 54.0 | 25.3 | 42.9 | 20.0 | 2.7 |
| FeaturePrint kNN k=5 | 59.5 | 58.3 | 28.9 | 46.7 | 23.3 | 2.7 |
| FeaturePrint kNN k=5 + reject | 56.5 | 55.2 | 28.9 | 52.4 | 36.7 | 2.7 |
| FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO) | 56.5 | 55.2 | 49.4 | 57.1 | 66.7 | 2.7 |
| CLIP ViT-L/14 zero-shot | 73.8 | 73.9 | 67.5 | 81.2 | 43.3 | 69.2 |
| CLIP ViT-L/14 kNN k=1 | 64.6 | 64.5 | 43.4 | 40.0 | 13.3 | 69.2 |
| CLIP ViT-L/14 kNN k=5 | 67.3 | 66.8 | 44.6 | 87.5 | 23.3 | 69.2 |
| CLIP ViT-L/14 kNN k=5 + reject | 63.9 | 63.3 | 36.1 | 37.5 | 30.0 | 69.2 |
| CLIP ViT-L/14 kNN k=5 + reject, +iPad gallery (LOSO) | 63.9 | 63.3 | 50.6 | 37.5 | 50.0 | 69.2 |
| PE-Core-S/16-384 zero-shot | 76.2 | 75.9 | 62.7 | 89.5 | 56.7 | 16.9 |
| PE-Core-S/16-384 kNN k=1 | 67.0 | 67.1 | 44.6 | 38.1 | 26.7 | 16.9 |
| PE-Core-S/16-384 kNN k=5 | 71.5 | 71.0 | 47.0 | 45.0 | 30.0 | 16.9 |
| PE-Core-S/16-384 kNN k=5 + reject | 67.9 | 67.0 | 43.4 | 44.0 | 36.7 | 16.9 |
| PE-Core-S/16-384 kNN k=5 + reject, +iPad gallery (LOSO) | 67.9 | 67.0 | 62.7 | 62.5 | 66.7 | 16.9 |
| SigLIP so400m/14 (v1) zero-shot | 83.2 | 83.0 | 72.3 | 92.0 | 76.7 | 229.1 |
| SigLIP so400m/14 (v1) kNN k=1 | 77.1 | 77.9 | 51.8 | 75.0 | 30.0 | 229.1 |
| SigLIP so400m/14 (v1) kNN k=5 | 80.2 | 80.5 | 56.6 | 75.0 | 30.0 | 229.1 |
| SigLIP so400m/14 (v1) kNN k=5 + reject | 76.2 | 76.4 | 56.6 | 58.8 | 33.3 | 229.1 |
| SigLIP so400m/14 (v1) kNN k=5 + reject, +iPad gallery (LOSO) | 76.2 | 76.4 | 66.3 | 67.9 | 63.3 | 229.1 |
| F1 Detector AND FP-kNN agree | 18.4 | 16.8 | 12.0 | 28.4 | 96.7 | 14.8 |
| F2 Detector, else FP-kNN(reject) | 48.9 | 47.5 | 30.1 | 66.7 | 33.3 | 14.8 |
| F3 Detector unless VNClassify=none | 24.3 | 22.1 | 20.5 | 37.0 | 66.7 | 17.3 |
| PE-Core-S/16-384 zero-shot + reject | 72.3 | 72.0 | 55.4 | 62.5 | 83.3 | 16.9 |
| F4 PE-Core-S/16-384: ZS, none if detector disagrees | 56.2 | 56.0 | 42.2 | 33.3 | 63.3 | 29.0 |
| F5 PE-Core-S/16-384: ZS AND same-embedding kNN agree | 62.2 | 61.6 | 41.0 | 40.0 | 86.7 | 16.9 |
| F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none | 71.3 | 70.8 | 59.0 | 66.7 | 80.0 | 16.9 |
| SigLIP so400m/14 (v1) zero-shot + reject | 79.0 | 78.8 | 68.7 | 71.8 | 93.3 | 229.1 |
| F4 SigLIP so400m/14 (v1): ZS, none if detector disagrees | 60.5 | 60.4 | 45.8 | 40.6 | 86.7 | 241.6 |
| F5 SigLIP so400m/14 (v1): ZS AND same-embedding kNN agree | 74.2 | 74.3 | 53.0 | 47.5 | 96.7 | 229.1 |
| F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none | 78.8 | 78.6 | 67.5 | 71.1 | 90.0 | 229.1 |
| Recorded, objects in RoomPlan categories only (n=37) | | | 83.8 | | | |
| Recorded, detector-only categories (n=46) | | | 54.3 | | | |

The recorded scan label comes from RoomPlan for RoomPlan categories (bed, chair, table, storage, sink, toilet, bathtub, television...) and from the multi-frame detector otherwise, so it is not directly comparable to single-image classifiers on those classes.

- FeaturePrint kNN k=5 + reject: reject if nearest cosine distance > 0.370 (95th pct of correct public CV)
- FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO): iPad only: gallery adds iPad photos (incl. `none`) from the other scans, leave-one-scan-out; public columns = same as k=5 + reject
- CLIP ViT-L/14 zero-shot: device mps; ms = image encoder incl. preprocessing
- CLIP ViT-L/14 kNN k=5 + reject: reject if nearest cosine distance > 0.282 (95th pct of correct public CV)
- CLIP ViT-L/14 kNN k=5 + reject, +iPad gallery (LOSO): iPad only: gallery adds iPad photos (incl. `none`) from the other scans, leave-one-scan-out; public columns = same as k=5 + reject
- PE-Core-S/16-384 zero-shot: device mps; ms = image encoder incl. preprocessing
- PE-Core-S/16-384 kNN k=5 + reject: reject if nearest cosine distance > 0.278 (95th pct of correct public CV)
- PE-Core-S/16-384 kNN k=5 + reject, +iPad gallery (LOSO): iPad only: gallery adds iPad photos (incl. `none`) from the other scans, leave-one-scan-out; public columns = same as k=5 + reject
- SigLIP so400m/14 (v1) zero-shot: device mps; ms = image encoder incl. preprocessing
- SigLIP so400m/14 (v1) kNN k=5 + reject: reject if nearest cosine distance > 0.317 (95th pct of correct public CV)
- SigLIP so400m/14 (v1) kNN k=5 + reject, +iPad gallery (LOSO): iPad only: gallery adds iPad photos (incl. `none`) from the other scans, leave-one-scan-out; public columns = same as k=5 + reject
- PE-Core-S/16-384 zero-shot + reject: none if label probability < 0.47 (5th pct of correct public)
- F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none: iPad only uses the other scans' photos; on public it equals ZS + (kNN distance reject)
- SigLIP so400m/14 (v1) zero-shot + reject: none if label probability < 0.59 (5th pct of correct public)
- F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none: iPad only uses the other scans' photos; on public it equals ZS + (kNN distance reject)

## Per-class top-1 accuracy, public split (%)

| Class (n) | Detector (app thresholds) | VNClassify (t=0.02) | FeaturePrint kNN k=1 | FeaturePrint kNN k=5 | CLIP ViT-L/14 zero-shot | PE-Core-S/16-384 zero-shot | SigLIP so400m/14 (v1) zero-shot | CLIP ViT-L/14 kNN k=5 | PE-Core-S/16-384 kNN k=5 | SigLIP so400m/14 (v1) kNN k=5 |
|---|---|---|---|---|---|---|---|---|---|---|
| scooter (38) | 58 | 26 | 95 | 97 | 100 | 100 | 100 | 97 | 100 | 100 |
| vacuum (60) | 30 | 28 | 77 | 82 | 90 | 97 | 100 | 88 | 95 | 100 |
| bicycle (40) | 42 | 85 | 70 | 80 | 90 | 95 | 100 | 88 | 95 | 92 |
| chair (77) | 69 | 68 | 60 | 62 | 83 | 77 | 81 | 65 | 62 | 65 |
| sofa (40) | 42 | 35 | 35 | 45 | 45 | 72 | 78 | 52 | 48 | 57 |
| bed (40) | 28 | 42 | 57 | 70 | 75 | 78 | 82 | 65 | 72 | 72 |
| table (80) | 18 | 39 | 24 | 28 | 39 | 59 | 71 | 20 | 28 | 50 |
| storage (155) | 35 | 70 | 61 | 71 | 77 | 80 | 83 | 81 | 85 | 83 |
| shelf (28) | 18 | 0 | 14 | 11 | 36 | 25 | 36 | 4 | 14 | 14 |
| lamp (40) | 10 | 52 | 62 | 72 | 88 | 88 | 80 | 75 | 70 | 85 |
| television (40) | 72 | 80 | 60 | 62 | 62 | 82 | 78 | 60 | 78 | 92 |
| monitor (40) | 5 | 60 | 38 | 48 | 75 | 75 | 85 | 25 | 62 | 52 |
| laptop (40) | 78 | 72 | 60 | 78 | 78 | 90 | 90 | 78 | 75 | 80 |
| refrigerator (40) | 57 | 52 | 60 | 55 | 80 | 78 | 70 | 55 | 55 | 70 |
| toilet (40) | 0 | 75 | 52 | 50 | 92 | 78 | 90 | 85 | 78 | 88 |
| sink (40) | 0 | 55 | 38 | 48 | 80 | 75 | 90 | 70 | 55 | 85 |
| bathtub (40) | 0 | 65 | 65 | 75 | 85 | 82 | 92 | 85 | 78 | 88 |
| mirror (40) | 30 | 0 | 65 | 72 | 50 | 57 | 90 | 70 | 75 | 92 |
| plant (40) | 8 | 68 | 65 | 60 | 85 | 82 | 78 | 68 | 70 | 75 |
| rug (44) | 18 | 0 | 70 | 77 | 77 | 80 | 86 | 70 | 89 | 86 |
| suitcase (40) | 25 | 40 | 30 | 42 | 65 | 75 | 82 | 55 | 45 | 72 |
| backpack (40) | 18 | 8 | 42 | 48 | 80 | 68 | 85 | 48 | 45 | 48 |
| bag (40) | 2 | 0 | 35 | 38 | 40 | 20 | 30 | 55 | 65 | 60 |
| trash can (40) | 5 | 20 | 40 | 42 | 70 | 75 | 80 | 70 | 85 | 92 |
| box (29) | 3 | 45 | 7 | 14 | 48 | 52 | 41 | 21 | 34 | 45 |
| guitar (40) | 35 | 60 | 75 | 75 | 90 | 85 | 98 | 82 | 90 | 90 |
| heater (36) | 0 | 0 | 78 | 72 | 81 | 69 | 72 | 92 | 81 | 89 |
| radiator (40) | 0 | 0 | 55 | 57 | 70 | 65 | 90 | 78 | 65 | 92 |
| ironing board (37) | 0 | 0 | 27 | 24 | 68 | 81 | 95 | 59 | 62 | 92 |
| stroller (40) | 0 | 15 | 38 | 40 | 68 | 70 | 85 | 75 | 70 | 85 |
| shower curtain (40) | 0 | 30 | 78 | 90 | 60 | 78 | 90 | 68 | 82 | 88 |
| towel rack (40) | 0 | 0 | 40 | 60 | 57 | 75 | 85 | 85 | 88 | 92 |
| fan (21) | 14 | 81 | 76 | 62 | 95 | 100 | 100 | 90 | 81 | 100 |
| ceiling fan (36) | 11 | 14 | 92 | 92 | 97 | 97 | 100 | 92 | 97 | 100 |
| cart (40) | 10 | 8 | 48 | 42 | 82 | 82 | 60 | 40 | 85 | 90 |
| ladder (40) | 28 | 0 | 42 | 52 | 70 | 65 | 95 | 70 | 62 | 92 |
| ottoman (40) | 12 | 0 | 52 | 60 | 80 | 70 | 95 | 68 | 75 | 90 |
| microwave (40) | 45 | 48 | 65 | 68 | 85 | 92 | 90 | 80 | 90 | 92 |
| washerDryer (40) | 62 | 57 | 72 | 78 | 88 | 85 | 98 | 85 | 90 | 95 |
| yoga mat (24) | 17 | 4 | 42 | 33 | 75 | 83 | 92 | 58 | 62 | 88 |

Detector-vocabulary gaps: the detector has no prompt for bathtub, ceiling fan, radiator, shower curtain, sink, toilet, towel rack (RoomPlan covers bathtub/sink/toilet in the app), so it scores 0 on those by construction.

## Per-class top-1 accuracy, iPad split (%; real objects only)

| Class (n) | Recorded detector | Detector (app thresholds) | VNClassify (t=0.02) | FeaturePrint kNN k=1 | FeaturePrint kNN k=5 | CLIP ViT-L/14 zero-shot | PE-Core-S/16-384 zero-shot | SigLIP so400m/14 (v1) zero-shot | CLIP ViT-L/14 kNN k=5 | PE-Core-S/16-384 kNN k=5 | SigLIP so400m/14 (v1) kNN k=5 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| art (1) | 100 | 100 | 100 | 0 | 0 | 100 | 100 | 0 | 0 | 0 | 0 |
| backpack (4) | 50 | 0 | 0 | 0 | 0 | 75 | 50 | 75 | 0 | 50 | 75 |
| bag (2) | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 50 | 0 | 0 |
| bathtub (2) | 100 | 0 | 100 | 0 | 0 | 100 | 100 | 100 | 100 | 50 | 50 |
| bean bag (1) | 100 | 0 | 0 | 0 | 0 | 0 | 100 | 100 | 0 | 0 | 0 |
| bed (9) | 67 | 44 | 67 | 67 | 78 | 100 | 67 | 67 | 67 | 56 | 78 |
| bicycle (2) | 100 | 50 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| box (7) | 0 | 0 | 57 | 0 | 0 | 86 | 100 | 100 | 14 | 86 | 100 |
| cart (3) | 0 | 0 | 0 | 0 | 0 | 33 | 33 | 67 | 0 | 0 | 33 |
| chair (6) | 83 | 33 | 33 | 50 | 50 | 50 | 67 | 83 | 33 | 17 | 33 |
| clothes rack (3) | 0 | 0 | 0 | 0 | 0 | 67 | 0 | 33 | 0 | 0 | 0 |
| coat rack (1) | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 100 | 0 | 0 | 0 |
| fan (2) | 100 | 0 | 0 | 100 | 100 | 100 | 100 | 100 | 100 | 100 | 100 |
| ladder (2) | 0 | 0 | 0 | 50 | 50 | 50 | 50 | 0 | 100 | 0 | 0 |
| lamp (2) | 100 | 100 | 0 | 0 | 0 | 100 | 0 | 100 | 0 | 0 | 100 |
| laptop (6) | 100 | 50 | 50 | 0 | 17 | 50 | 83 | 67 | 100 | 50 | 83 |
| ottoman (1) | 0 | 100 | 0 | 0 | 0 | 0 | 0 | 100 | 0 | 0 | 0 |
| scooter (3) | 33 | 33 | 0 | 33 | 67 | 100 | 100 | 100 | 100 | 100 | 100 |
| shelf (2) | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 50 | 0 | 0 | 0 |
| sink (4) | 100 | 0 | 100 | 50 | 75 | 75 | 75 | 100 | 100 | 100 | 100 |
| storage (6) | 100 | 33 | 50 | 17 | 17 | 50 | 33 | 17 | 33 | 67 | 17 |
| table (3) | 100 | 0 | 67 | 0 | 0 | 67 | 67 | 100 | 0 | 33 | 0 |
| television (5) | 60 | 0 | 0 | 0 | 0 | 80 | 80 | 100 | 20 | 60 | 80 |
| toilet (2) | 100 | 0 | 100 | 100 | 50 | 100 | 100 | 100 | 100 | 50 | 50 |
| trash can (4) | 100 | 25 | 0 | 25 | 25 | 50 | 50 | 50 | 25 | 25 | 50 |

## Top-10 confusion pairs (public split, truth -> predicted, count)

**Detector (app thresholds)**: storage->none 49; toilet->none 35; bathtub->none 35; towel rack->none 35; sink->none 34; bag->none 34; cart->none 32; stroller->none 31; shower curtain->none 30; ceiling fan->none 30

**Detector (app thr., largest-box pick)**: storage->none 49; toilet->none 35; bathtub->none 35; towel rack->none 35; sink->none 34; bag->none 34; cart->none 32; stroller->none 31; shower curtain->none 30; ceiling fan->none 30

**VNClassify (t=0.02)**: table->storage 18; mirror->art 17; rug->art 16; backpack->suitcase 16; ceiling fan->lamp 15; scooter->bicycle 15; shelf->storage 14; bag->suitcase 13; bed->pillow 12; rug->none 12

**FeaturePrint kNN k=5**: table->storage 21; shelf->storage 10; television->monitor 10; monitor->television 10; sink->bathtub 10; sofa->ottoman 9; backpack->bag 9; bag->backpack 9; bag->suitcase 9; toilet->sink 8

**FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO)**: table->storage 19; television->none 11; box->none 11; sink->bathtub 10; shelf->storage 9; monitor->television 9; backpack->bag 9; bag->backpack 9; bag->suitcase 9; sofa->ottoman 8

**CLIP ViT-L/14 zero-shot**: table->storage 16; shelf->storage 14; television->monitor 13; bag->backpack 13; stroller->cart 10; sofa->ottoman 9; storage->table 9; laptop->monitor 8; table->chair 7; suitcase->bag 7

**PE-Core-S/16-384 zero-shot**: bag->backpack 21; table->storage 13; shelf->storage 13; storage->table 11; chair->table 10; shower curtain->none 7; monitor->laptop 6; mirror->sink 6; trash can->toilet 6; heater->fan 6

**PE-Core-S/16-384 kNN k=5**: table->storage 21; table->chair 15; backpack->bag 15; shelf->storage 13; chair->table 10; television->monitor 9; box->storage 8; monitor->laptop 7; sink->toilet 7; sink->bathtub 7

**PE-Core-S/16-384 kNN k=5 + reject, +iPad gallery (LOSO)**: table->storage 20; backpack->bag 15; table->chair 14; shelf->storage 12; chair->table 10; television->none 9; storage->none 8; television->monitor 7; monitor->laptop 7; sink->toilet 7

**SigLIP so400m/14 (v1) zero-shot**: shelf->storage 14; bag->backpack 14; cart->suitcase 13; table->storage 11; storage->table 11; bag->suitcase 10; chair->table 9; television->monitor 9; lamp->none 7; refrigerator->storage 5

**SigLIP so400m/14 (v1) kNN k=5**: table->storage 19; shelf->storage 18; backpack->bag 16; monitor->laptop 11; chair->table 10; chair->sofa 7; storage->table 7; bag->backpack 7; bag->suitcase 7; box->storage 7

**SigLIP so400m/14 (v1) kNN k=5 + reject, +iPad gallery (LOSO)**: table->storage 18; shelf->storage 15; backpack->bag 15; storage->none 10; monitor->laptop 10; chair->table 9; television->none 9; plant->none 9; box->none 8; storage->table 7

**F2 Detector, else FP-kNN(reject)**: monitor->television 23; table->chair 15; bed->storage 14; shelf->storage 11; backpack->bag 10; plant->vase 9; bag->suitcase 9; table->storage 8; storage->shelf 8; sink->bathtub 8

**PE-Core-S/16-384 zero-shot + reject**: bag->backpack 18; table->none 16; mirror->none 15; storage->none 14; box->none 13; shelf->storage 12; shower curtain->none 11; towel rack->none 11; storage->table 10; backpack->none 10

**F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none**: bag->backpack 21; shelf->storage 13; table->storage 12; storage->none 11; chair->table 10; storage->table 10; television->none 9; shower curtain->none 8; box->none 7; ironing board->none 7

**SigLIP so400m/14 (v1) zero-shot + reject**: storage->none 17; table->none 15; box->none 15; bag->none 14; bag->backpack 13; cart->suitcase 13; shelf->storage 12; table->storage 10; lamp->none 9; rug->none 9

**F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none**: bag->backpack 14; shelf->storage 13; cart->suitcase 13; storage->none 12; plant->none 11; table->storage 10; storage->table 10; lamp->none 10; bag->suitcase 10; television->none 9

## Top-10 confusion pairs (iPad split incl. `none`, truth -> predicted)

**Recorded detector**: box->bin 7; none->vacuum 4; none->mirror 3; none->heater 3; none->room divider 3; none->refrigerator 2; none->toy 2; none->workbench 2; none->humidifier 2; none->storage 2

**Detector (app thresholds)**: none->vacuum 5; sink->none 4; box->none 4; backpack->none 3; laptop->none 3; none->mirror 2; storage->microwave 2; bed->laptop 2; fan->none 2; television->laptop 2

**Detector (app thr., largest-box pick)**: none->vacuum 5; sink->none 4; box->none 4; backpack->none 3; laptop->none 3; none->mirror 2; fan->none 2; bag->none 2; television->none 2; trash can->none 2

**VNClassify (t=0.02)**: none->box 5; none->storage 4; none->art 3; none->sink 2; bed->pillow 2; television->art 2; bag->art 2; trash can->art 2; chair->suitcase 2; backpack->art 2

**FeaturePrint kNN k=5**: storage->refrigerator 4; none->ladder 4; none->washerDryer 3; none->mirror 3; chair->cart 2; none->storage 2; laptop->table 2; none->plant 2; television->yoga mat 2; backpack->plant 2

**FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO)**: none->television 2; none->ladder 2; none->washerDryer 2; none->mirror 2; laptop->box 2; trash can->none 2; chair->bed 2; clothes rack->none 2; box->none 2; sink->refrigerator 1

**CLIP ViT-L/14 zero-shot**: none->cart 4; none->trash can 4; none->heater 2; storage->refrigerator 2; laptop->monitor 2; bag->backpack 2; shelf->none 2; none->storage 2; chair->backpack 1; none->box 1

**PE-Core-S/16-384 zero-shot**: storage->sink 2; none->box 2; storage->refrigerator 2; bed->storage 2; lamp->storage 2; bag->backpack 2; trash can->toilet 2; none->microwave 2; backpack->table 1; none->cart 1

**PE-Core-S/16-384 kNN k=5**: none->ladder 5; none->storage 5; bed->storage 3; none->trash can 3; table->storage 2; none->chair 2; lamp->none 2; bag->backpack 2; none->ironing board 2; chair->suitcase 2

**PE-Core-S/16-384 kNN k=5 + reject, +iPad gallery (LOSO)**: none->box 2; lamp->none 2; bag->backpack 2; backpack->bag 2; clothes rack->none 2; cart->box 2; storage->none 1; chair->cart 1; backpack->none 1; none->lamp 1

**SigLIP so400m/14 (v1) zero-shot**: none->mirror 3; storage->refrigerator 3; storage->sink 2; bag->backpack 2; none->storage 2; ladder->cart 2; laptop->table 1; none->vacuum 1; bed->laptop 1; laptop->television 1

**SigLIP so400m/14 (v1) kNN k=5**: none->trash can 5; none->mirror 3; table->bed 3; chair->ottoman 2; none->box 2; none->ladder 2; none->bag 2; storage->bed 2; bag->backpack 2; chair->suitcase 2

**SigLIP so400m/14 (v1) kNN k=5 + reject, +iPad gallery (LOSO)**: none->box 5; none->bag 2; shelf->none 2; backpack->bag 2; clothes rack->none 2; storage->none 1; chair->laptop 1; backpack->none 1; none->trash can 1; none->television 1

**F2 Detector, else FP-kNN(reject)**: none->vacuum 5; none->mirror 2; none->washerDryer 2; none->ladder 2; storage->microwave 2; bed->laptop 2; laptop->table 2; none->plant 2; television->laptop 2; backpack->plant 2

**PE-Core-S/16-384 zero-shot + reject**: chair->none 3; storage->sink 2; backpack->none 2; storage->refrigerator 2; bed->storage 2; bag->backpack 2; television->none 2; trash can->toilet 2; none->vacuum 1; bean bag->none 1

**F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none**: none->box 2; storage->refrigerator 2; bed->storage 2; lamp->none 2; bag->backpack 2; trash can->toilet 2; clothes rack->none 2; storage->none 1; backpack->none 1; none->cart 1

**SigLIP so400m/14 (v1) zero-shot + reject**: storage->refrigerator 3; bed->none 3; storage->sink 2; bag->backpack 2; clothes rack->none 2; none->storage 2; ladder->cart 2; laptop->table 1; table->none 1; laptop->television 1

**F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none**: storage->refrigerator 3; bag->backpack 2; shelf->none 2; clothes rack->none 2; ladder->cart 2; storage->none 1; laptop->table 1; backpack->none 1; none->vacuum 1; storage->sink 1

## iPad hard cases (every iPad photo the recorded scan got wrong)

Cells show the prediction; **bold** = right (truth, or `none` for a non-object/fixture).

| Photo | Truth (object) | Recorded | Detector (app thresholds) | VNClassify (t=0.02) | FeaturePrint kNN k=5 + reject | FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO) | CLIP ViT-L/14 zero-shot | PE-Core-S/16-384 zero-shot | SigLIP so400m/14 (v1) zero-shot | F2 Detector, else FP-kNN(reject) | F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none | F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-24T21-35-31_B76C9B61 | backpack (backpack) | bag | none | art | plant | bag | **backpack** | **backpack** | **backpack** | plant | **backpack** | **backpack** |
| 2026-10-24T21-35-31_1FF89EA4 | backpack (backpack on floor) | vacuum | bed | bed | vacuum | ottoman | bed | suitcase | refrigerator | bed | suitcase | refrigerator |
| 2026-10-24T19-43-54_FD6CD8DF | bed (bed) | other | **bed** | **bed** | **bed** | **bed** | **bed** | storage | none | **bed** | storage | none |
| 2026-10-24T17-39-03_D048193B | bed (bed (corner)) | laptop | **bed** | pillow | **bed** | **bed** | **bed** | **bed** | bean bag | **bed** | **bed** | bean bag |
| 2026-10-24T17-56-45_24FFD0F1 | bed (bunk bed ladder + mini fridge) | ladder | storage | storage | cart | none | **bed** | suitcase | **bed** | storage | suitcase | **bed** |
| 2026-10-25T02-01-29_644162E4 | box (cardboard box) | bin | none | **box** | towel rack | **box** | **box** | **box** | **box** | towel rack | **box** | **box** |
| 2026-10-25T02-01-29_E9F85714 | box (cardboard box) | bin | backpack | **box** | yoga mat | **box** | backpack | **box** | **box** | backpack | **box** | **box** |
| 2026-10-25T02-05-43_18257B6B | box (cardboard box) | bin | toy | **box** | storage | **box** | **box** | **box** | **box** | toy | **box** | **box** |
| 2026-10-25T02-05-43_457C4553 | box (cardboard box) | bin | none | **box** | storage | **box** | **box** | **box** | **box** | storage | **box** | **box** |
| 2026-10-25T02-05-43_4AADD146 | box (cardboard box) | bin | toy | art | table | trash can | **box** | **box** | **box** | toy | **box** | **box** |
| 2026-10-25T02-05-43_81686442 | box (cardboard box) | bin | none | none | shower curtain | shower curtain | **box** | **box** | **box** | shower curtain | **box** | **box** |
| 2026-10-25T02-01-29_AD10D510 | box (cardboard boxes) | bin | none | art | ladder | none | **box** | **box** | **box** | ladder | **box** | **box** |
| 2026-10-25T02-01-29_41B06125 | cart (furniture dolly) | yoga mat | yoga mat | box | ottoman | box | ottoman | **cart** | **cart** | yoga mat | **cart** | **cart** |
| 2026-10-25T02-01-29_4426C67D | cart (furniture dolly) | vacuum | none | art | towel rack | none | backpack | mirror | ottoman | towel rack | mirror | none |
| 2026-10-25T02-05-43_71E5E585 | cart (furniture dolly) | yoga mat | bin | box | rug | **cart** | **cart** | box | **cart** | bin | box | **cart** |
| 2026-10-24T21-35-31_655BE7AB | chair (office chair (partial)) | other | bed | basket | bathtub | bed | bed | bed | none | bed | bed | none |
| 2026-10-25T02-01-29_2C3C0F81 | clothes rack (clothes rack with hangers) | sewing machine | none | art | radiator | none | **clothes rack** | ironing board | bed | radiator | none | none |
| 2026-10-25T02-01-29_552B14A6 | clothes rack (clothes rack with hangers) | crib | none | bed | storage | box | **clothes rack** | bed | **clothes rack** | storage | bed | **clothes rack** |
| 2026-10-25T02-01-29_80EAEC37 | clothes rack (wire garment rack (+ step ladder)) | room divider | chair | table | ladder | none | cart | cart | ladder | chair | none | none |
| 2026-10-25T02-01-29_C36C8113 | coat rack (coat/garment stand base) | vacuum | none | art | ladder | ladder | cart | cart | **coat rack** | ladder | none | none |
| 2026-10-25T02-01-29_6426004E | ladder (rolling step ladder) | chair | chair | table | table | table | cart | cart | cart | chair | cart | cart |
| 2026-10-25T02-01-29_B4817201 | ladder (rolling step ladder) | vacuum | chair | table | **ladder** | **ladder** | **ladder** | **ladder** | cart | chair | none | cart |
| 2026-10-24T08-53-59_A625D0FE | ottoman (ottoman / cube stool) | chair | **ottoman** | bed | bed | bed | storage | storage | **ottoman** | **ottoman** | storage | **ottoman** |
| 2026-10-25T02-01-29_72066CED | scooter (e-scooter) | shoe rack | none | art | shower curtain | bag | **scooter** | **scooter** | **scooter** | shower curtain | **scooter** | **scooter** |
| 2026-10-25T02-05-43_AC5DB808 | scooter (e-scooter) | vacuum | **scooter** | skateboard | **scooter** | **scooter** | **scooter** | **scooter** | **scooter** | **scooter** | **scooter** | **scooter** |
| 2026-10-24T17-56-45_DD4F1671 | television (TV (close-up of screen)) | air purifier | none | none | yoga mat | **television** | **television** | art | **television** | yoga mat | art | **television** |
| 2026-10-24T17-56-45_72E3E565 | television (wall-mounted TV) | none | laptop | laptop | monitor | **television** | **television** | **television** | **television** | laptop | **television** | **television** |
| 2026-10-25T02-05-43_FF8CA209 | none (black plastic sheeting) | workbench | workbench | box | yoga mat | television | trash can | trash can | **none** | workbench | **none** | **none** |
| 2026-10-25T02-01-29_2DCF0F49 | none (black plastic sheeting / trash bags) | bean bag | **none** | box | trash can | **none** | trash can | **none** | **none** | trash can | **none** | **none** |
| 2026-10-25T02-05-43_4A00F91C | none (black plastic sheeting / trash bags) | bag | **none** | plant | yoga mat | **none** | trash can | **none** | **shower curtain** | yoga mat | **none** | **none** |
| 2026-10-24T07-07-37_9A873C14 | none (blackboard / projection screen on wall) | refrigerator | refrigerator | storage | mirror | mirror | cart | **none** | **none** | refrigerator | **none** | **none** |
| 2026-10-24T07-07-37_4389ABCA | none (broom and dustpan) | vacuum | vacuum | sink | ladder | ladder | cart | vacuum | vacuum | vacuum | **none** | vacuum |
| 2026-10-24T17-39-03_60BFD08C | none (clothes pile) | toy | **none** | toy | plant | **none** | **none** | table | **none** | plant | **none** | **none** |
| 2026-10-24T19-43-54_9728009E | none (clothes pile) | toy | **none** | art | plant | **none** | **none** | storage | **none** | plant | **none** | **none** |
| 2026-10-24T21-35-31_D6F9A183 | none (clothes pile) | bag | **none** | **none** | **towel rack** | **none** | **none** | **none** | **none** | **towel rack** | **none** | **none** |
| 2026-10-24T21-35-31_CE53F088 | none (door) | storage | vacuum | **shower curtain** | bathtub | washerDryer | **none** | **none** | **none** | vacuum | **none** | **none** |
| 2026-10-24T17-39-03_C7983797 | none (door frame) | room divider | **none** | art | **shower curtain** | **shower curtain** | shelf | **none** | **none** | **shower curtain** | **none** | **none** |
| 2026-10-24T21-35-31_C87A696A | none (doorway) | storage | mirror | sink | mirror | mirror | **towel rack** | mirror | **none** | mirror | mirror | **none** |
| 2026-10-25T02-01-29_5FF8B685 | none (electrical panel) | television | **none** | storage | guitar | **none** | storage | microwave | storage | guitar | **none** | **none** |
| 2026-10-25T02-05-43_7B8F64DE | none (electrical panel) | television | **none** | **none** | **towel rack** | **none** | storage | microwave | storage | **towel rack** | **none** | **none** |
| 2026-10-24T07-07-37_3DD1C719 | none (floor mop) | vacuum | **none** | **none** | **towel rack** | **none** | heater | cart | **none** | **towel rack** | cart | **none** |
| 2026-10-24T07-07-37_52CFB458 | none (interior window) | mirror | **none** | box | **none** | **none** | box | box | **none** | **none** | box | **none** |
| 2026-10-24T07-07-37_88AB7D5D | none (interior window / fire extinguisher) | mirror | vacuum | box | **none** | **none** | table | box | **none** | vacuum | box | **none** |
| 2026-10-24T07-07-37_05F7E338 | none (interior window / wall) | refrigerator | mirror | box | storage | television | **none** | **none** | **none** | mirror | **none** | **none** |
| 2026-10-24T07-07-37_CC2F7191 | none (light stand (tripod)) | vacuum | **none** | **none** | ladder | **none** | cart | **none** | **none** | ladder | **none** | **none** |
| 2026-10-24T07-07-37_ECF24331 | none (light stand (tripod) with sandbag) | vacuum | vacuum | chair | storage | clothes rack | cart | **none** | mirror | vacuum | **none** | **none** |
| 2026-10-24T17-39-03_87E24272 | none (radiator) | heater | laptop | laptop | vacuum | box | heater | laptop | toilet | laptop | laptop | toilet |
| 2026-10-24T19-43-54_1162E1D1 | none (radiator) | heater | **none** | art | **shower curtain** | **none** | **radiator** | **radiator** | **radiator** | **shower curtain** | **none** | **radiator** |
| 2026-10-24T21-35-31_DDA1762D | none (radiator) | heater | **none** | toilet | washerDryer | **none** | **radiator** | **radiator** | **radiator** | washerDryer | **none** | **radiator** |
| 2026-10-24T19-43-54_D28DCA97 | none (shower curtain) | room divider | **none** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** | **shower curtain** |
| 2026-10-25T02-05-43_02A716D2 | none (structural pole) | room divider | vacuum | storage | ladder | ladder | coat rack | **none** | mirror | vacuum | **none** | **none** |
| 2026-10-24T19-43-54_02F7BF6A | none (towel rack) | workbench | **none** | treadmill | ironing board | **none** | **towel rack** | **towel rack** | **towel rack** | ironing board | **none** | **none** |
| 2026-10-24T21-35-31_20327CC7 | none (towel rack) | humidifier | **none** | **shower curtain** | **none** | **none** | **towel rack** | **towel rack** | **towel rack** | **none** | **none** | **none** |
| 2026-10-24T21-35-31_FAB486ED | none (towel rack) | crib | **none** | bed | **none** | **none** | **towel rack** | ironing board | **towel rack** | **none** | **none** | **none** |
| 2026-10-24T19-43-54_AEA164D9 | none (towel rack / shower wall) | humidifier | **none** | **shower curtain** | ladder | **none** | **towel rack** | **towel rack** | **towel rack** | ladder | **none** | **none** |
| 2026-10-24T07-07-37_637B707B | none (wall (sign, paper-towel dispenser)) | mirror | **none** | storage | washerDryer | washerDryer | trash can | **none** | **none** | washerDryer | **none** | **none** |
| 2026-10-24T17-39-03_A24707FA | none (wall switch plate) | art | **none** | **none** | **towel rack** | **towel rack** | art | sink | mirror | **towel rack** | sink | mirror |
| 2026-10-25T02-01-29_912FC200 | unclear (clutter: boards, step ladder) | refrigerator | chair | box | storage | none | cart | cart | none | chair | none | none |
| 2026-10-25T02-05-43_F227F60B | unclear (dark flat panel leaning on wall (monitor/board?)) | vacuum | none | art | ironing board | trash can | monitor | box | box | ironing board | box | box |
| 2026-10-24T17-39-03_EBDCE727 | unclear (dark object on floor (bag?)) | bag | none | art | backpack | none | storage | none | art | backpack | none | none |
| 2026-10-25T02-01-29_D178EE22 | unclear (unclear blurry boxy object) | air purifier | none | art | storage | none | radiator | sink | none | storage | none | none |
| 2026-10-24T17-39-03_0CE28DD6 | unclear (unclear dark corner) | trash can | none | none | suitcase | bag | storage | storage | mirror | suitcase | storage | mirror |
| 2026-10-24T07-07-37_703059D0 | unclear (unclear white panel) | basket | none | none | shower curtain | shower curtain | none | box | trash can | shower curtain | box | trash can |
| 2026-10-24T07-07-37_997D7D5B | unclear (white panel (partition or door)) | room divider | none | storage | shower curtain | none | none | none | none | shower curtain | none | none |

Correct among these 64 hard cases (excl. unclear): Detector (app thresholds): 24; VNClassify (t=0.02): 14; FeaturePrint kNN k=5 + reject: 15; FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO): 31; CLIP ViT-L/14 zero-shot: 31; PE-Core-S/16-384 zero-shot: 31; SigLIP so400m/14 (v1) zero-shot: 41; F2 Detector, else FP-kNN(reject): 14; F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none: 37; F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none: 44

## FeaturePrint kNN: reject-threshold sweep on iPad (reference only; the reported threshold is tuned on public)

| nearest-distance threshold | iPad top-1 % | none precision % | none recall % |
|---|---|---|---|
| 0.200 | 1.2 | 26.6 | 96.7 |
| 0.250 | 13.3 | 30.9 | 83.3 |
| 0.300 | 27.7 | 45.0 | 60.0 |
| 0.350 | 28.9 | 50.0 | 40.0 |
| 0.400 | 28.9 | 52.9 | 30.0 |
| 0.450 | 28.9 | 46.7 | 23.3 |
| 0.500 | 28.9 | 46.7 | 23.3 |
| 0.600 | 28.9 | 46.7 | 23.3 |
| 0.370 (tuned) | 28.9 | 52.4 | 36.7 |

## Crop size / vocabulary check (public split)

```
min-side quartiles [119. 217. 480.]
Detector (app thresholds)                [0,150): acc 9% none 74% n=616 [150,300): acc 29% none 40% n=445 [300,600): acc 35% none 31% n=455 [600,9999): acc 38% none 24% n=229
Detector (app thr., largest-box pick)    [0,150): acc 10% none 74% n=616 [150,300): acc 33% none 40% n=445 [300,600): acc 40% none 31% n=455 [600,9999): acc 41% none 24% n=229
VNClassify (t=0.02)                      [0,150): acc 19% none 17% n=616 [150,300): acc 42% none 4% n=445 [300,600): acc 55% none 4% n=455 [600,9999): acc 47% none 6% n=229
FeaturePrint kNN k=5                     [0,150): acc 45% none 0% n=616 [150,300): acc 57% none 0% n=445 [300,600): acc 71% none 0% n=455 [600,9999): acc 80% none 0% n=229
```

Subset: in-vocabulary classes and min side >= 150 px (n=985)
| Method | top-1 % on subset |
|---|---|
| Detector (app thresholds) | 37.7 |
| Detector (any score >= 0.15) | 40.6 |
| Detector (app thr., largest-box pick) | 42.4 |
| VNClassify (t=0.02) | 47.5 |
| FeaturePrint kNN k=1 | 61.1 |
| FeaturePrint kNN k=5 | 66.3 |
| FeaturePrint kNN k=5 + reject | 62.2 |
| FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO) | 62.2 |
| CLIP ViT-L/14 zero-shot | 77.9 |
| CLIP ViT-L/14 kNN k=1 | 68.1 |
| CLIP ViT-L/14 kNN k=5 | 71.8 |
| CLIP ViT-L/14 kNN k=5 + reject | 66.4 |
| CLIP ViT-L/14 kNN k=5 + reject, +iPad gallery (LOSO) | 66.4 |
| PE-Core-S/16-384 zero-shot | 81.4 |
| PE-Core-S/16-384 kNN k=1 | 70.4 |
| PE-Core-S/16-384 kNN k=5 | 75.2 |
| PE-Core-S/16-384 kNN k=5 + reject | 69.3 |
| PE-Core-S/16-384 kNN k=5 + reject, +iPad gallery (LOSO) | 69.3 |
| SigLIP so400m/14 (v1) zero-shot | 83.7 |
| SigLIP so400m/14 (v1) kNN k=1 | 77.6 |
| SigLIP so400m/14 (v1) kNN k=5 | 80.8 |
| SigLIP so400m/14 (v1) kNN k=5 + reject | 74.0 |
| SigLIP so400m/14 (v1) kNN k=5 + reject, +iPad gallery (LOSO) | 74.0 |
| F1 Detector AND FP-kNN agree | 28.9 |
| F2 Detector, else FP-kNN(reject) | 52.8 |
| F3 Detector unless VNClassify=none | 37.2 |
| PE-Core-S/16-384 zero-shot + reject | 78.9 |
| F4 PE-Core-S/16-384: ZS, none if detector disagrees | 54.9 |
| F5 PE-Core-S/16-384: ZS AND same-embedding kNN agree | 68.7 |
| F6 PE-Core-S/16-384: ZS, none if LOSO-kNN (iPad negatives) says none | 73.9 |
| SigLIP so400m/14 (v1) zero-shot + reject | 80.0 |
| F4 SigLIP so400m/14 (v1): ZS, none if detector disagrees | 55.0 |
| F5 SigLIP so400m/14 (v1): ZS AND same-embedding kNN agree | 74.7 |
| F6 SigLIP so400m/14 (v1): ZS, none if LOSO-kNN (iPad negatives) says none | 76.4 |

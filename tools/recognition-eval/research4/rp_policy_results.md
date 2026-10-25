# Classifier re-check of RoomPlan objects (research4)

Classifier: PE-Core-S/16-384 auto photo, V4 probe lam=1 + none bias +1, merges backpack->bag, monitor->television, shelf->storage; fixtures (radiator/shower curtain/towel rack) = none. Thresholds tuned leave-one-scan-out.


## RP (true RoomPlan origin): 28 photos, 7 scans, real 28, none 0, unclear 0

| policy | thresholds chosen per held-out scan | top-1 real % | none P % | none R % | #pred none | fixes | breaks | wrong->other wrong |
|---|---|---|---|---|---|---|---|---|
| a | - | 96.4 (27/28) | n/a | n/a | 0 | 0 | 0 | 0 |
| b | never | 96.4 (27/28) | n/a | n/a | 0 | 0 | 0 | 0 |
| c | never | 96.4 (27/28) | n/a | n/a | 0 | 0 | 0 | 0 |
| c+b | m=inf,t=never | 96.4 (27/28) | n/a | n/a | 0 | 0 | 0 | 0 |
| d | never | 96.4 (27/28) | n/a | n/a | 0 | 0 | 0 | 0 |

Fixed thresholds (not tuned; shows the curve):

| policy | threshold | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| b | 0.3 | 96.4 | n/a | n/a | 0 | 0 |
| b | 0.5 | 96.4 | n/a | n/a | 0 | 0 |
| b | 0.7 | 96.4 | n/a | n/a | 0 | 0 |
| b | 0.9 | 96.4 | n/a | n/a | 0 | 0 |
| c | 0.3 | 92.9 | n/a | n/a | 0 | 1 |
| c | 0.5 | 92.9 | n/a | n/a | 0 | 1 |
| c | 0.7 | 96.4 | n/a | n/a | 0 | 0 |
| c | 0.9 | 96.4 | n/a | n/a | 0 | 0 |
| d | 0.0 | 71.4 | n/a | n/a | 0 | 7 |
| d | 0.3 | 82.1 | n/a | n/a | 0 | 4 |
| d | 0.5 | 82.1 | n/a | n/a | 0 | 4 |
| d | 0.7 | 89.3 | n/a | n/a | 0 | 2 |
| d | 0.9 | 96.4 | n/a | n/a | 0 | 0 |

Multi-view (auto + top-3 strict keyframes, mean prob; 20 photos in 6 scans with frames), LOSO:

| policy | key | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| a | auto | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| a | multi-view | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| b | auto | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| b | multi-view | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| c | auto | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| c | multi-view | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| d | auto | 100.0 (n=20) | n/a | n/a | 0 | 0 |
| d | multi-view | 100.0 (n=20) | n/a | n/a | 0 | 0 |

## CAT (recorded label is a RoomPlan category, any origin): 42 photos, 10 scans, real 35, none 6, unclear 1

| policy | thresholds chosen per held-out scan | top-1 real % | none P % | none R % | #pred none | fixes | breaks | wrong->other wrong |
|---|---|---|---|---|---|---|---|---|
| a | - | 94.3 (33/35) | n/a | 0.0 | 0 | 0 | 0 | 0 |
| b | 0.4, 0.6 | 94.3 (33/35) | 100.0 | 50.0 | 3 | 3 | 0 | 0 |
| c | never | 94.3 (33/35) | n/a | 0.0 | 0 | 0 | 0 | 0 |
| c+b | m=inf,t=0.4, m=inf,t=0.6 | 94.3 (33/35) | 100.0 | 50.0 | 3 | 3 | 0 | 0 |
| d | 0.6, 0.9, never | 88.6 (31/35) | n/a | 0.0 | 0 | 0 | 2 | 2 |

Fixed thresholds (not tuned; shows the curve):

| policy | threshold | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| b | 0.3 | 94.3 | 100.0 | 66.7 | 4 | 0 |
| b | 0.5 | 94.3 | 100.0 | 50.0 | 3 | 0 |
| b | 0.7 | 94.3 | 100.0 | 33.3 | 2 | 0 |
| b | 0.9 | 94.3 | 100.0 | 16.7 | 1 | 0 |
| c | 0.3 | 91.4 | n/a | 0.0 | 0 | 1 |
| c | 0.5 | 91.4 | n/a | 0.0 | 0 | 1 |
| c | 0.7 | 94.3 | n/a | 0.0 | 0 | 0 |
| c | 0.9 | 94.3 | n/a | 0.0 | 0 | 0 |
| d | 0.0 | 71.4 | 100.0 | 66.7 | 4 | 8 |
| d | 0.3 | 80.0 | 100.0 | 66.7 | 4 | 5 |
| d | 0.5 | 82.9 | 100.0 | 50.0 | 3 | 4 |
| d | 0.7 | 88.6 | 100.0 | 33.3 | 2 | 2 |
| d | 0.9 | 94.3 | 100.0 | 16.7 | 1 | 0 |

Multi-view (auto + top-3 strict keyframes, mean prob; 31 photos in 6 scans with frames), LOSO:

| policy | key | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| a | auto | 96.2 (n=26) | n/a | 0.0 | 0 | 0 |
| a | multi-view | 96.2 (n=26) | n/a | 0.0 | 0 | 0 |
| b | auto | 96.2 (n=26) | 100.0 | 25.0 | 1 | 0 |
| b | multi-view | 96.2 (n=26) | n/a | 0.0 | 0 | 0 |
| c | auto | 96.2 (n=26) | n/a | 0.0 | 0 | 0 |
| c | multi-view | 96.2 (n=26) | n/a | 0.0 | 0 | 0 |
| d | auto | 92.3 (n=26) | n/a | 0.0 | 0 | 1 |
| d | multi-view | 88.5 (n=26) | 100.0 | 25.0 | 1 | 2 |

## DET-RPcat (detector objects with RoomPlan-category labels): 14 photos, 7 scans, real 7, none 6, unclear 1

| policy | thresholds chosen per held-out scan | top-1 real % | none P % | none R % | #pred none | fixes | breaks | wrong->other wrong |
|---|---|---|---|---|---|---|---|---|
| a | - | 85.7 (6/7) | n/a | 0.0 | 0 | 0 | 0 | 0 |
| b | 0.4, 0.6 | 85.7 (6/7) | 100.0 | 50.0 | 3 | 3 | 0 | 0 |
| c | never | 85.7 (6/7) | n/a | 0.0 | 0 | 0 | 0 | 0 |
| c+b | m=inf,t=0.4, m=inf,t=0.6 | 85.7 (6/7) | 100.0 | 50.0 | 3 | 3 | 0 | 0 |
| d | 0.4, 0.6 | 85.7 (6/7) | 100.0 | 50.0 | 3 | 3 | 0 | 2 |

Fixed thresholds (not tuned; shows the curve):

| policy | threshold | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| b | 0.3 | 85.7 | 100.0 | 66.7 | 4 | 0 |
| b | 0.5 | 85.7 | 100.0 | 50.0 | 3 | 0 |
| b | 0.7 | 85.7 | 100.0 | 33.3 | 2 | 0 |
| b | 0.9 | 85.7 | 100.0 | 16.7 | 1 | 0 |
| c | 0.3 | 85.7 | n/a | 0.0 | 0 | 0 |
| c | 0.5 | 85.7 | n/a | 0.0 | 0 | 0 |
| c | 0.7 | 85.7 | n/a | 0.0 | 0 | 0 |
| c | 0.9 | 85.7 | n/a | 0.0 | 0 | 0 |
| d | 0.0 | 71.4 | 100.0 | 66.7 | 4 | 1 |
| d | 0.3 | 71.4 | 100.0 | 66.7 | 4 | 1 |
| d | 0.5 | 85.7 | 100.0 | 50.0 | 3 | 0 |
| d | 0.7 | 85.7 | 100.0 | 33.3 | 2 | 0 |
| d | 0.9 | 85.7 | 100.0 | 16.7 | 1 | 0 |

Multi-view (auto + top-3 strict keyframes, mean prob; 11 photos in 6 scans with frames), LOSO:

| policy | key | top-1 real % | none P % | none R % | fixes | breaks |
|---|---|---|---|---|---|---|
| a | auto | 83.3 (n=6) | n/a | 0.0 | 0 | 0 |
| a | multi-view | 83.3 (n=6) | n/a | 0.0 | 0 | 0 |
| b | auto | 83.3 (n=6) | 100.0 | 25.0 | 1 | 0 |
| b | multi-view | 66.7 (n=6) | 50.0 | 25.0 | 1 | 1 |
| c | auto | 83.3 (n=6) | n/a | 0.0 | 0 | 0 |
| c | multi-view | 83.3 (n=6) | n/a | 0.0 | 0 | 0 |
| d | auto | 83.3 (n=6) | 100.0 | 25.0 | 1 | 0 |
| d | multi-view | 66.7 (n=6) | 100.0 | 25.0 | 1 | 1 |

## Per object: RP (true RoomPlan origin)

| scan | id | recorded | truth (object) | clf top-2 | p(none) | p(recorded) | b t=0.9 | c m=0.5 | d m=0.5 |
|---|---|---|---|---|---|---|---|---|---|
| 10-24T03-57 | 1FEB623E | sink | sink (sink) | sink 1.00, bathtub 0.00 | 0.00 | 1.00 | sink | sink | sink |
| 10-24T03-57 | 74BF85B7 | storage | storage (sink base cabinet) | sink 0.69, storage 0.13 | 0.03 | 0.13 | storage | storage | **sink** (BREAK) |
| 10-24T07-07 | 59B52952 | sink | sink (sink) | sink 0.99, storage 0.00 | 0.00 | 0.99 | sink | sink | sink |
| 10-24T07-07 | 8E360936 | storage | storage (sink base cabinet) | sink 0.47, storage 0.20 | 0.03 | 0.20 | storage | storage | storage |
| 10-24T08-53 | D9D5E421 | bed | bed (bed) | bed 0.51, storage 0.44 | 0.00 | 0.51 | bed | bed | bed |
| 10-24T08-53 | A625D0FE | chair | ottoman (ottoman / cube stool) | storage 0.89, bed 0.05 | 0.00 | 0.00 | chair | chair | **storage** |
| 10-24T08-53 | 0CC27606 | storage | storage (cabinet holding microwave + mini fridge) | refrigerator 0.86, microwave 0.09 | 0.00 | 0.04 | storage | storage | **refrigerator** (BREAK) |
| 10-24T08-53 | 5D88AEAE | table | table (desk) | storage 0.67, bag 0.17 | 0.00 | 0.03 | table | **storage** (BREAK) | **storage** (BREAK) |
| 10-24T17-39 | DFFD405C | chair | chair (office chair) | chair 0.57, ottoman 0.13 | 0.04 | 0.57 | chair | chair | chair |
| 10-24T17-56 | 021E3708 | bed | bed (bed) | bed 0.97, storage 0.01 | 0.01 | 0.97 | bed | bed | bed |
| 10-24T17-56 | A84F814B | bed | bed (bunk bed) | bed 0.98, storage 0.01 | 0.00 | 0.98 | bed | bed | bed |
| 10-24T17-56 | 12747CDA | chair | chair (office chair) | chair 0.95, ironing board 0.02 | 0.00 | 0.95 | chair | chair | chair |
| 10-24T17-56 | 2A2E7826 | storage | storage (cabinet holding microwave + mini fridge) | refrigerator 0.82, storage 0.07 | 0.00 | 0.07 | storage | storage | **refrigerator** (BREAK) |
| 10-24T19-43 | EB850947 | bathtub | bathtub (bathtub) | bathtub 0.84, none 0.09 | 0.09 | 0.84 | bathtub | bathtub | bathtub |
| 10-24T19-43 | EF5C4023 | bed | bed (bed) | bed 0.88, storage 0.07 | 0.01 | 0.88 | bed | bed | bed |
| 10-24T19-43 | C702EE67 | chair | chair (office chair) | chair 0.55, bag 0.22 | 0.01 | 0.55 | chair | chair | chair |
| 10-24T19-43 | 81878440 | sink | sink (sink) | sink 0.95, toilet 0.04 | 0.01 | 0.95 | sink | sink | sink |
| 10-24T19-43 | 69623E38 | storage | storage (open cabinet / nightstand unit) | storage 0.83, table 0.12 | 0.00 | 0.83 | storage | storage | storage |
| 10-24T19-43 | 431CE7CF | table | table (desk) | table 0.82, storage 0.13 | 0.00 | 0.82 | table | table | table |
| 10-24T19-43 | 88370757 | toilet | toilet (toilet) | toilet 0.68, none 0.30 | 0.30 | 0.68 | toilet | toilet | toilet |
| 10-24T21-35 | 22189622 | bathtub | bathtub (bathtub) | bathtub 0.66, sink 0.13 | 0.12 | 0.66 | bathtub | bathtub | bathtub |
| 10-24T21-35 | 878C3DDC | bed | bed (bunk bed) | bed 0.64, storage 0.22 | 0.00 | 0.64 | bed | bed | bed |
| 10-24T21-35 | E1752554 | bed | bed (bed) | bed 0.93, storage 0.02 | 0.01 | 0.93 | bed | bed | bed |
| 10-24T21-35 | 5DC86A38 | chair | chair (office chair) | chair 0.20, stroller 0.19 | 0.16 | 0.20 | chair | chair | chair |
| 10-24T21-35 | 8CBF2EE7 | sink | sink (sink) | toilet 0.35, sink 0.33 | 0.29 | 0.33 | sink | sink | sink |
| 10-24T21-35 | A52459F5 | storage | storage (open cabinet / nightstand unit) | table 0.53, storage 0.42 | 0.00 | 0.42 | storage | storage | storage |
| 10-24T21-35 | E7BD1FAC | table | table (desk) | table 0.94, storage 0.03 | 0.00 | 0.94 | table | table | table |
| 10-24T21-35 | CF372892 | toilet | toilet (toilet) | toilet 0.92, none 0.05 | 0.05 | 0.92 | toilet | toilet | toilet |

## Per object: DET-RPcat (detector objects with RoomPlan-category labels)

| scan | id | recorded | truth (object) | clf top-2 | p(none) | p(recorded) | b t=0.9 | c m=0.5 | d m=0.5 |
|---|---|---|---|---|---|---|---|---|---|
| 10-24T07-05 | 6130EBF7 | chair | chair (folding chair) | chair 0.23, table 0.23 | 0.08 | 0.23 | chair | chair | chair |
| 10-24T07-07 | 05F7E338 | refrigerator | none (interior window / wall) | none 0.64, storage 0.26 | 0.64 | 0.00 | refrigerator | refrigerator | **none** (fix) |
| 10-24T07-07 | 9A873C14 | refrigerator | none (blackboard / projection screen on wall) | none 0.92, mirror 0.03 | 0.92 | 0.01 | **none** (fix) | refrigerator | **none** (fix) |
| 10-24T17-39 | BC4FD280 | television | television (wall-mounted TV) | television 0.68, table 0.09 | 0.07 | 0.68 | television | television | television |
| 10-24T19-43 | 8DE6477F | storage | storage (wall shelf) | storage 0.40, none 0.26 | 0.26 | 0.40 | storage | storage | storage |
| 10-24T19-43 | B8E4E8C1 | television | television (wall-mounted TV) | television 0.83, mirror 0.12 | 0.01 | 0.83 | television | television | television |
| 10-24T21-35 | C87A696A | storage | none (doorway) | mirror 0.85, none 0.09 | 0.09 | 0.01 | storage | storage | **mirror** |
| 10-24T21-35 | CE53F088 | storage | none (door) | none 0.83, storage 0.08 | 0.83 | 0.08 | storage | storage | **none** (fix) |
| 10-24T21-35 | E2DD8E8D | storage | storage (wall shelf) | storage 0.34, none 0.14 | 0.14 | 0.34 | storage | storage | storage |
| 10-24T21-35 | D469489A | television | television (wall-mounted TV) | mirror 0.56, television 0.24 | 0.05 | 0.24 | television | television | television |
| 10-25T02-01 | 6426004E | chair | ladder (rolling step ladder) | cart 0.97, ladder 0.03 | 0.00 | 0.00 | chair | chair | **cart** |
| 10-25T02-01 | 912FC200 | refrigerator | unclear (clutter: boards, step ladder) | cart 0.47, none 0.22 | 0.22 | 0.01 | refrigerator | refrigerator | refrigerator |
| 10-25T02-01 | 5FF8B685 | television | none (electrical panel) | none 0.49, microwave 0.11 | 0.49 | 0.08 | television | television | television |
| 10-25T02-05 | 7B8F64DE | television | none (electrical panel) | television 0.38, microwave 0.32 | 0.13 | 0.38 | television | television | television |

## RoomPlan categories vs classifier vocabulary

- bathtub: expressible; family for policy c = ['bathtub', 'sink', 'toilet']
- bed: expressible; family for policy c = ['bed', 'sofa']
- chair: expressible; family for policy c = ['bean bag', 'chair', 'ottoman', 'sofa']
- dishwasher: NOT expressible; family for policy c = (none: keep)
- fireplace: NOT expressible; family for policy c = (none: keep)
- oven: NOT expressible; family for policy c = ['microwave']
- refrigerator: expressible; family for policy c = ['microwave', 'refrigerator', 'storage', 'washerDryer']
- sink: expressible; family for policy c = ['bathtub', 'sink', 'toilet']
- sofa: expressible; family for policy c = ['bean bag', 'bed', 'chair', 'ottoman', 'sofa']
- stairs: NOT expressible; family for policy c = (none: keep)
- storage: expressible; family for policy c = ['storage', 'table']
- stove: NOT expressible; family for policy c = (none: keep)
- table: expressible; family for policy c = ['ottoman', 'storage', 'table']
- television: expressible; family for policy c = ['television']
- toilet: expressible; family for policy c = ['bathtub', 'sink', 'toilet']
- washerDryer: expressible; family for policy c = ['refrigerator', 'washerDryer']

## p(none) tail, all iPad photos (none_tail.py)
```
t=0.3: real rejected 5/83 [('de', 'bean bag', 'bean bag', 0.41), ('de', 'lamp', 'lamp', 0.39), ('de', 'air purifier', 'television', 0.4), ('de', 'trash can', 'trash can', 0.31), ('de', 'art', 'art', 0.62)] | none caught 21/30
t=0.4: real rejected 2/83 [('de', 'bean bag', 'bean bag', 0.41), ('de', 'art', 'art', 0.62)] | none caught 20/30
t=0.5: real rejected 1/83 [('de', 'art', 'art', 0.62)] | none caught 19/30
t=0.6: real rejected 1/83 [('de', 'art', 'art', 0.62)] | none caught 15/30
t=0.7: real rejected 0/83 [] | none caught 12/30
t=0.8: real rejected 0/83 [] | none caught 10/30
t=0.9: real rejected 0/83 [] | none caught 6/30
```

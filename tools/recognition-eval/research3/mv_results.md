# Multi-keyframe vs single auto photo (PE-Core-S/16-384 + V4 probe lam=1, merges)

Objects: 96 (real 70, none 21, unclear 5) from 6 scans with saved frames.
Auto-photo embedding check vs research2 cache: min cos 1.0000 over 96 photos.
Views per object (strict CropPicker gates): {0: 31, 1: 26, 2: 19, 3: 9, 4: 4, 5: 2, 6: 4, 7: 1}; relaxed: {0: 8, 1: 20, 2: 22, 3: 13, 4: 14, 5: 12, 6: 1, 7: 3, 9: 3}

| method | pool | pad | k | +auto | top-1 real % | none P % | none R % | changed vs auto (fixed/broken) |
|---|---|---|---|---|---|---|---|---|
| single auto photo | - | - | - | - | 70.0 | 93.8 | 71.4 | - |
| best frame | strict | 1.0 | 1 |  | 74.3 | 76.5 | 61.9 | 10/9 |
| mean-emb | strict | 1.0 | 3 |  | 71.4 | 72.2 | 61.9 | 9/10 |
| mean-emb | strict | 1.0 | 5 |  | 71.4 | 72.2 | 61.9 | 9/10 |
| mean-emb | strict | 1.0 | all |  | 71.4 | 72.2 | 61.9 | 9/10 |
| vote | strict | 1.0 | 3 |  | 74.3 | 73.7 | 66.7 | 10/8 |
| vote | strict | 1.0 | 5 |  | 74.3 | 73.7 | 66.7 | 10/8 |
| vote | strict | 1.0 | all |  | 74.3 | 73.7 | 66.7 | 10/8 |
| max-conf | strict | 1.0 | 3 |  | 75.7 | 78.9 | 71.4 | 11/7 |
| max-conf | strict | 1.0 | 5 |  | 74.3 | 75.0 | 71.4 | 10/7 |
| max-conf | strict | 1.0 | all |  | 74.3 | 75.0 | 71.4 | 10/7 |
| mean-prob | strict | 1.0 | 3 |  | 75.7 | 77.8 | 66.7 | 11/8 |
| mean-prob | strict | 1.0 | 5 |  | 74.3 | 73.7 | 66.7 | 10/8 |
| mean-prob | strict | 1.0 | all |  | 74.3 | 73.7 | 66.7 | 10/8 |
| best frame | strict | 1.0 | 1 | y | 71.4 | 80.0 | 57.1 | 5/7 |
| mean-emb | strict | 1.0 | 3 | y | 72.9 | 81.2 | 61.9 | 7/7 |
| mean-emb | strict | 1.0 | 5 | y | 71.4 | 76.5 | 61.9 | 6/7 |
| mean-emb | strict | 1.0 | all | y | 71.4 | 76.5 | 61.9 | 6/7 |
| vote | strict | 1.0 | 3 | y | 75.7 | 77.8 | 66.7 | 7/4 |
| vote | strict | 1.0 | 5 | y | 75.7 | 77.8 | 66.7 | 7/4 |
| vote | strict | 1.0 | all | y | 75.7 | 77.8 | 66.7 | 7/4 |
| max-conf | strict | 1.0 | 3 | y | 75.7 | 78.9 | 71.4 | 9/5 |
| max-conf | strict | 1.0 | 5 | y | 74.3 | 75.0 | 71.4 | 8/5 |
| max-conf | strict | 1.0 | all | y | 74.3 | 75.0 | 71.4 | 8/5 |
| mean-prob | strict | 1.0 | 3 | y | 75.7 | 83.3 | 71.4 | 8/4 |
| mean-prob | strict | 1.0 | 5 | y | 74.3 | 78.9 | 71.4 | 7/4 |
| mean-prob | strict | 1.0 | all | y | 74.3 | 78.9 | 71.4 | 7/4 |
| best frame | strict | 1.3 | 1 |  | 70.0 | 80.0 | 57.1 | 5/8 |
| mean-emb | strict | 1.3 | 3 |  | 67.1 | 80.0 | 57.1 | 5/10 |
| mean-emb | strict | 1.3 | 5 |  | 67.1 | 80.0 | 57.1 | 5/10 |
| mean-emb | strict | 1.3 | all |  | 67.1 | 80.0 | 57.1 | 5/10 |
| vote | strict | 1.3 | 3 |  | 70.0 | 81.2 | 61.9 | 6/8 |
| vote | strict | 1.3 | 5 |  | 68.6 | 76.5 | 61.9 | 5/8 |
| vote | strict | 1.3 | all |  | 67.1 | 76.5 | 61.9 | 5/9 |
| max-conf | strict | 1.3 | 3 |  | 70.0 | 81.2 | 61.9 | 6/8 |
| max-conf | strict | 1.3 | 5 |  | 70.0 | 81.2 | 61.9 | 6/8 |
| max-conf | strict | 1.3 | all |  | 70.0 | 81.2 | 61.9 | 6/8 |
| mean-prob | strict | 1.3 | 3 |  | 70.0 | 81.2 | 61.9 | 6/8 |
| mean-prob | strict | 1.3 | 5 |  | 70.0 | 81.2 | 61.9 | 6/8 |
| mean-prob | strict | 1.3 | all |  | 70.0 | 81.2 | 61.9 | 6/8 |
| best frame | strict | 1.3 | 1 | y | 68.6 | 86.7 | 61.9 | 3/6 |
| mean-emb | strict | 1.3 | 3 | y | 68.6 | 86.7 | 61.9 | 5/8 |
| mean-emb | strict | 1.3 | 5 | y | 68.6 | 86.7 | 61.9 | 5/8 |
| mean-emb | strict | 1.3 | all | y | 68.6 | 86.7 | 61.9 | 5/8 |
| vote | strict | 1.3 | 3 | y | 71.4 | 87.5 | 66.7 | 4/4 |
| vote | strict | 1.3 | 5 | y | 70.0 | 82.4 | 66.7 | 3/4 |
| vote | strict | 1.3 | all | y | 70.0 | 82.4 | 66.7 | 3/4 |
| max-conf | strict | 1.3 | 3 | y | 71.4 | 87.5 | 66.7 | 5/5 |
| max-conf | strict | 1.3 | 5 | y | 71.4 | 87.5 | 66.7 | 5/5 |
| max-conf | strict | 1.3 | all | y | 71.4 | 87.5 | 66.7 | 5/5 |
| mean-prob | strict | 1.3 | 3 | y | 71.4 | 86.7 | 61.9 | 4/5 |
| mean-prob | strict | 1.3 | 5 | y | 71.4 | 86.7 | 61.9 | 4/5 |
| mean-prob | strict | 1.3 | all | y | 71.4 | 86.7 | 61.9 | 4/5 |
| best frame | strict | 1.6 | 1 |  | 68.6 | 78.6 | 52.4 | 5/10 |
| mean-emb | strict | 1.6 | 3 |  | 70.0 | 78.6 | 52.4 | 6/10 |
| mean-emb | strict | 1.6 | 5 |  | 68.6 | 78.6 | 52.4 | 5/10 |
| mean-emb | strict | 1.6 | all |  | 68.6 | 78.6 | 52.4 | 5/10 |
| vote | strict | 1.6 | 3 |  | 68.6 | 82.4 | 66.7 | 6/8 |
| vote | strict | 1.6 | 5 |  | 67.1 | 77.8 | 66.7 | 5/8 |
| vote | strict | 1.6 | all |  | 68.6 | 82.4 | 66.7 | 6/8 |
| max-conf | strict | 1.6 | 3 |  | 67.1 | 81.2 | 61.9 | 6/10 |
| max-conf | strict | 1.6 | 5 |  | 68.6 | 86.7 | 61.9 | 7/10 |
| max-conf | strict | 1.6 | all |  | 68.6 | 86.7 | 61.9 | 7/10 |
| mean-prob | strict | 1.6 | 3 |  | 68.6 | 82.4 | 66.7 | 6/8 |
| mean-prob | strict | 1.6 | 5 |  | 70.0 | 82.4 | 66.7 | 6/7 |
| mean-prob | strict | 1.6 | all |  | 71.4 | 87.5 | 66.7 | 7/7 |
| best frame | strict | 1.6 | 1 | y | 68.6 | 86.7 | 61.9 | 2/5 |
| mean-emb | strict | 1.6 | 3 | y | 70.0 | 86.7 | 61.9 | 4/6 |
| mean-emb | strict | 1.6 | 5 | y | 68.6 | 86.7 | 61.9 | 3/6 |
| mean-emb | strict | 1.6 | all | y | 68.6 | 86.7 | 61.9 | 3/6 |
| vote | strict | 1.6 | 3 | y | 72.9 | 87.5 | 66.7 | 4/3 |
| vote | strict | 1.6 | 5 | y | 71.4 | 82.4 | 66.7 | 3/3 |
| vote | strict | 1.6 | all | y | 72.9 | 87.5 | 66.7 | 4/3 |
| max-conf | strict | 1.6 | 3 | y | 71.4 | 87.5 | 66.7 | 4/4 |
| max-conf | strict | 1.6 | 5 | y | 72.9 | 93.3 | 66.7 | 5/4 |
| max-conf | strict | 1.6 | all | y | 72.9 | 93.3 | 66.7 | 5/4 |
| mean-prob | strict | 1.6 | 3 | y | 72.9 | 88.2 | 71.4 | 5/3 |
| mean-prob | strict | 1.6 | 5 | y | 72.9 | 88.2 | 71.4 | 5/3 |
| mean-prob | strict | 1.6 | all | y | 74.3 | 93.8 | 71.4 | 6/3 |
| best frame | relaxed | 1.0 | 1 |  | 68.6 | 65.0 | 61.9 | 12/15 |
| mean-emb | relaxed | 1.0 | 3 |  | 71.4 | 61.9 | 61.9 | 12/13 |
| mean-emb | relaxed | 1.0 | 5 |  | 72.9 | 61.9 | 61.9 | 12/12 |
| mean-emb | relaxed | 1.0 | all |  | 71.4 | 61.9 | 61.9 | 12/13 |
| vote | relaxed | 1.0 | 3 |  | 72.9 | 63.6 | 66.7 | 14/13 |
| vote | relaxed | 1.0 | 5 |  | 72.9 | 61.9 | 61.9 | 14/14 |
| vote | relaxed | 1.0 | all |  | 72.9 | 61.9 | 61.9 | 14/14 |
| max-conf | relaxed | 1.0 | 3 |  | 74.3 | 73.7 | 66.7 | 13/11 |
| max-conf | relaxed | 1.0 | 5 |  | 72.9 | 68.4 | 61.9 | 12/12 |
| max-conf | relaxed | 1.0 | all |  | 72.9 | 68.4 | 61.9 | 12/12 |
| mean-prob | relaxed | 1.0 | 3 |  | 75.7 | 70.0 | 66.7 | 15/12 |
| mean-prob | relaxed | 1.0 | 5 |  | 74.3 | 66.7 | 66.7 | 14/12 |
| mean-prob | relaxed | 1.0 | all |  | 74.3 | 66.7 | 66.7 | 14/12 |
| best frame | relaxed | 1.0 | 1 | y | 70.0 | 80.0 | 57.1 | 6/9 |
| mean-emb | relaxed | 1.0 | 3 | y | 70.0 | 76.5 | 61.9 | 7/9 |
| mean-emb | relaxed | 1.0 | 5 | y | 70.0 | 70.6 | 57.1 | 6/9 |
| mean-emb | relaxed | 1.0 | all | y | 70.0 | 70.6 | 57.1 | 6/9 |
| vote | relaxed | 1.0 | 3 | y | 77.1 | 76.2 | 76.2 | 12/6 |
| vote | relaxed | 1.0 | 5 | y | 77.1 | 76.2 | 76.2 | 12/6 |
| vote | relaxed | 1.0 | all | y | 77.1 | 76.2 | 76.2 | 12/6 |
| max-conf | relaxed | 1.0 | 3 | y | 80.0 | 84.2 | 76.2 | 13/5 |
| max-conf | relaxed | 1.0 | 5 | y | 78.6 | 78.9 | 71.4 | 12/6 |
| max-conf | relaxed | 1.0 | all | y | 78.6 | 78.9 | 71.4 | 12/6 |
| mean-prob | relaxed | 1.0 | 3 | y | 78.6 | 80.0 | 76.2 | 12/5 |
| mean-prob | relaxed | 1.0 | 5 | y | 77.1 | 76.2 | 76.2 | 11/5 |
| mean-prob | relaxed | 1.0 | all | y | 77.1 | 76.2 | 76.2 | 11/5 |
| best frame | relaxed | 1.3 | 1 |  | 64.3 | 62.5 | 47.6 | 6/15 |
| mean-emb | relaxed | 1.3 | 3 |  | 67.1 | 70.6 | 57.1 | 9/14 |
| mean-emb | relaxed | 1.3 | 5 |  | 68.6 | 70.6 | 57.1 | 9/13 |
| mean-emb | relaxed | 1.3 | all |  | 70.0 | 70.6 | 57.1 | 9/12 |
| vote | relaxed | 1.3 | 3 |  | 67.1 | 68.4 | 61.9 | 11/15 |
| vote | relaxed | 1.3 | 5 |  | 65.7 | 66.7 | 66.7 | 10/14 |
| vote | relaxed | 1.3 | all |  | 65.7 | 66.7 | 66.7 | 10/14 |
| max-conf | relaxed | 1.3 | 3 |  | 68.6 | 75.0 | 57.1 | 10/14 |
| max-conf | relaxed | 1.3 | 5 |  | 68.6 | 75.0 | 57.1 | 10/14 |
| max-conf | relaxed | 1.3 | all |  | 70.0 | 75.0 | 57.1 | 10/13 |
| mean-prob | relaxed | 1.3 | 3 |  | 68.6 | 72.2 | 61.9 | 11/14 |
| mean-prob | relaxed | 1.3 | 5 |  | 68.6 | 73.7 | 66.7 | 11/13 |
| mean-prob | relaxed | 1.3 | all |  | 70.0 | 73.7 | 66.7 | 11/12 |
| best frame | relaxed | 1.3 | 1 | y | 67.1 | 81.2 | 61.9 | 4/8 |
| mean-emb | relaxed | 1.3 | 3 | y | 67.1 | 76.5 | 61.9 | 7/11 |
| mean-emb | relaxed | 1.3 | 5 | y | 70.0 | 76.5 | 61.9 | 7/9 |
| mean-emb | relaxed | 1.3 | all | y | 70.0 | 76.5 | 61.9 | 7/9 |
| vote | relaxed | 1.3 | 3 | y | 71.4 | 78.9 | 71.4 | 8/7 |
| vote | relaxed | 1.3 | 5 | y | 72.9 | 75.0 | 71.4 | 8/6 |
| vote | relaxed | 1.3 | all | y | 72.9 | 75.0 | 71.4 | 8/6 |
| max-conf | relaxed | 1.3 | 3 | y | 72.9 | 82.4 | 66.7 | 8/7 |
| max-conf | relaxed | 1.3 | 5 | y | 71.4 | 82.4 | 66.7 | 8/8 |
| max-conf | relaxed | 1.3 | all | y | 72.9 | 82.4 | 66.7 | 8/7 |
| mean-prob | relaxed | 1.3 | 3 | y | 71.4 | 77.8 | 66.7 | 8/8 |
| mean-prob | relaxed | 1.3 | 5 | y | 74.3 | 78.9 | 71.4 | 9/6 |
| mean-prob | relaxed | 1.3 | all | y | 74.3 | 78.9 | 71.4 | 9/6 |
| best frame | relaxed | 1.6 | 1 |  | 65.7 | 62.5 | 47.6 | 7/15 |
| mean-emb | relaxed | 1.6 | 3 |  | 68.6 | 62.5 | 47.6 | 9/15 |
| mean-emb | relaxed | 1.6 | 5 |  | 67.1 | 62.5 | 47.6 | 8/15 |
| mean-emb | relaxed | 1.6 | all |  | 68.6 | 62.5 | 47.6 | 8/14 |
| vote | relaxed | 1.6 | 3 |  | 67.1 | 70.0 | 66.7 | 10/13 |
| vote | relaxed | 1.6 | 5 |  | 65.7 | 66.7 | 66.7 | 9/13 |
| vote | relaxed | 1.6 | all |  | 67.1 | 66.7 | 66.7 | 9/12 |
| max-conf | relaxed | 1.6 | 3 |  | 65.7 | 66.7 | 57.1 | 9/15 |
| max-conf | relaxed | 1.6 | 5 |  | 68.6 | 68.8 | 52.4 | 10/15 |
| max-conf | relaxed | 1.6 | all |  | 68.6 | 68.8 | 52.4 | 10/15 |
| mean-prob | relaxed | 1.6 | 3 |  | 67.1 | 70.0 | 66.7 | 10/13 |
| mean-prob | relaxed | 1.6 | 5 |  | 68.6 | 70.0 | 66.7 | 10/12 |
| mean-prob | relaxed | 1.6 | all |  | 68.6 | 70.0 | 66.7 | 10/12 |
| best frame | relaxed | 1.6 | 1 | y | 68.6 | 86.7 | 61.9 | 4/7 |
| mean-emb | relaxed | 1.6 | 3 | y | 68.6 | 81.2 | 61.9 | 6/9 |
| mean-emb | relaxed | 1.6 | 5 | y | 67.1 | 82.4 | 66.7 | 5/8 |
| mean-emb | relaxed | 1.6 | all | y | 67.1 | 82.4 | 66.7 | 5/8 |
| vote | relaxed | 1.6 | 3 | y | 74.3 | 78.9 | 71.4 | 8/5 |
| vote | relaxed | 1.6 | 5 | y | 74.3 | 75.0 | 71.4 | 8/5 |
| vote | relaxed | 1.6 | all | y | 74.3 | 75.0 | 71.4 | 8/5 |
| max-conf | relaxed | 1.6 | 3 | y | 71.4 | 82.4 | 66.7 | 7/7 |
| max-conf | relaxed | 1.6 | 5 | y | 72.9 | 86.7 | 61.9 | 8/8 |
| max-conf | relaxed | 1.6 | all | y | 72.9 | 86.7 | 61.9 | 8/8 |
| mean-prob | relaxed | 1.6 | 3 | y | 72.9 | 83.3 | 71.4 | 8/6 |
| mean-prob | relaxed | 1.6 | 5 | y | 74.3 | 83.3 | 71.4 | 9/6 |
| mean-prob | relaxed | 1.6 | all | y | 74.3 | 83.3 | 71.4 | 9/6 |

## Subset with >=1 strict view (n real = 47, none = 14)

| method | top-1 real % | none P % | none R % |
|---|---|---|---|
| auto photo | 63.8 | 90.9 | 71.4 |
| best frame, pad 1.3 | 63.8 | 70.0 | 50.0 |
| mean-emb all, pad 1.3 | 59.6 | 70.0 | 50.0 |
| mean-emb all + auto, pad 1.3 | 61.7 | 80.0 | 57.1 |
| vote all + auto, pad 1.3 | 63.8 | 75.0 | 64.3 |
| mean-emb 3 + auto, pad 1.3 | 61.7 | 80.0 | 57.1 |

## Per-object (hard cases + every object a multi-view method changed)

| scan | obj | truth (true_object) | detector | auto | best frame 1.3 | mean-emb all+auto 1.3 | vote all+auto 1.3 | #views strict/relaxed | per-view labels (strict, 1.3) |
|---|---|---|---|---|---|---|---|---|---|
| 17-39-03 | 0CE28DD6 | unclear (unclear dark corner) | trash can | storage | plant | none | none | 2/4 | plant, none |
| 17-39-03 | 0DBEFB88 | laptop (laptop) | laptop | mirror | laptop | television | television | 2/2 | laptop, television |
| 17-39-03 | 2E598B09 | laptop (laptop) | laptop | laptop | box | table | laptop | 3/5 | box, table, laptop |
| 17-39-03 | 60BFD08C | none (clothes pile) | toy | table | refrigerator | table | table | 1/3 | refrigerator |
| 17-39-03 | 87E24272 | none (radiator) | heater | laptop | laptop | laptop | laptop | 0/7 |  |
| 17-39-03 | EBDCE727 | unclear (dark object on floor (bag?)) | bag | plant | bag | trash can | plant | 6/7 | bag, plant, trash can, trash can, plant, mirror |
| 17-56-45 | 24FFD0F1 | bed (bunk bed ladder + mini fridge) | ladder | bag | bed | bed | bed | 2/4 | bed, bed |
| 17-56-45 | 45269E6D | lamp (floor lamp) | lamp | storage | none | none | none | 7/9 | none, none, none, lamp, bed, none, lamp |
| 17-56-45 | DD4F1671 | television (TV (close-up of screen)) | air purifier | mirror | box | box | box | 4/5 | box, storage, lamp, box |
| 19-43-54 | 1162E1D1 | none (radiator) | heater | none | none | none | none | 2/2 | none, none |
| 19-43-54 | 431CE7CF | table (desk) | table | table | storage | storage | table | 1/5 | storage |
| 19-43-54 | A4841057 | lamp (floor lamp) | lamp | storage | lamp | lamp | none | 5/5 | lamp, lamp, none, none, none |
| 19-43-54 | AEA164D9 | none (towel rack / shower wall) | humidifier | none | none | none | none | 0/0 |  |
| 19-43-54 | D28DCA97 | none (shower curtain) | room divider | none | none | none | none | 1/2 | none |
| 19-43-54 | FD6CD8DF | bed (bed) | other | bed | bed | storage | storage | 3/9 | bed, storage, storage |
| 21-35-31 | 1FF89EA4 | backpack (backpack on floor) | vacuum | suitcase | bag | bag | bag | 1/2 | bag |
| 21-35-31 | 5DC86A38 | chair (office chair) | chair | chair | stroller | stroller | stroller | 1/3 | stroller |
| 21-35-31 | 655BE7AB | chair (office chair (partial)) | other | bed | stroller | stroller | bed | 1/2 | stroller |
| 21-35-31 | D6F9A183 | none (clothes pile) | bag | none | table | bag | none | 3/3 | table, box, none |
| 21-35-31 | DDA1762D | none (radiator) | heater | none | none | none | none | 2/4 | none, none |
| 21-35-31 | E2DD8E8D | shelf (wall shelf) | shelf | storage | none | storage | storage | 1/4 | none |
| 21-35-31 | FAB486ED | none (towel rack) | crib | ironing board | ironing board | none | ironing board | 2/5 | ironing board, none |
| 02-01-29 | 2DCF0F49 | none (black plastic sheeting / trash bags) | bean bag | none | box | box | box | 2/2 | box, box |
| 02-01-29 | 41B06125 | cart (furniture dolly) | yoga mat | cart | box | box | box | 2/3 | box, box |
| 02-01-29 | 4426C67D | cart (furniture dolly) | vacuum | mirror | box | box | box | 1/4 | box |
| 02-01-29 | 5FF8B685 | none (electrical panel) | television | none | none | television | none | 3/4 | none, mirror, television |
| 02-01-29 | 6426004E | ladder (rolling step ladder) | chair | cart | ladder | ladder | ladder | 2/3 | ladder, ladder |
| 02-01-29 | 644162E4 | box (cardboard box) | bin | box | box | box | box | 1/2 | box |
| 02-01-29 | 72066CED | scooter (e-scooter) | shoe rack | scooter | scooter | scooter | scooter | 6/7 | scooter, bicycle, scooter, stroller, stroller, stroller |
| 02-01-29 | AD10D510 | box (cardboard boxes) | bin | box | box | box | box | 3/3 | box, box, box |
| 02-01-29 | B4817201 | ladder (rolling step ladder) | vacuum | ladder | ladder | ladder | ladder | 0/2 |  |
| 02-01-29 | C36C8113 | coat rack (coat/garment stand base) | vacuum | lamp | cart | cart | cart | 1/1 | cart |
| 02-01-29 | D178EE22 | unclear (unclear blurry boxy object) | air purifier | none | trash can | trash can | trash can | 1/1 | trash can |
| 02-01-29 | E7AB5A46 | scooter (e-scooter) | scooter | scooter | scooter | scooter | scooter | 5/5 | scooter, scooter, scooter, scooter, ladder |
| 02-01-29 | E9F85714 | box (cardboard box) | bin | box | box | box | box | 1/3 | box |
| 02-05-43 | 02A716D2 | none (structural pole) | room divider | none | yoga mat | none | none | 1/1 | yoga mat |
| 02-05-43 | 18257B6B | box (cardboard box) | bin | box | box | box | box | 0/5 |  |
| 02-05-43 | 457C4553 | box (cardboard box) | bin | box | box | box | box | 0/1 |  |
| 02-05-43 | 4AADD146 | box (cardboard box) | bin | box | box | box | box | 4/5 | box, box, box, box |
| 02-05-43 | 81686442 | box (cardboard box) | bin | box | box | box | box | 6/6 | box, box, box, box, box, box |
| 02-05-43 | AC5DB808 | scooter (e-scooter) | vacuum | scooter | scooter | scooter | scooter | 2/3 | scooter, scooter |
| 02-05-43 | F227F60B | unclear (dark flat panel leaning on wall (monitor/board?)) | vacuum | box | box | box | box | 1/5 | box |

 ('relaxed', 1.0, 3, 'max-conf', True)
  FIX 0DBEFB88 'laptop'                                 auto=mirror       -> laptop
  FIX 24FFD0F1 'bunk bed ladder + mini fridge'          auto=bag          -> bed
  chg 45269E6D 'floor lamp'                             auto=storage      -> none
  FIX 84C148DA 'laptop'                                 auto=table        -> laptop
  chg DD4F1671 'TV (close-up of screen)'                auto=mirror       -> none
  BRK 431CE7CF 'desk'                                   auto=table        -> storage
  FIX 9728009E 'clothes pile'                           auto=table        -> none
  FIX A4841057 'floor lamp'                             auto=storage      -> lamp
  BRK C702EE67 'office chair'                           auto=chair        -> trash can
  FIX 1FF89EA4 'backpack on floor'                      auto=suitcase     -> bag
  FIX 8CBF2EE7 'sink'                                   auto=toilet       -> sink
  FIX A52459F5 'open cabinet / nightstand unit'         auto=table        -> storage
  BRK E2DD8E8D 'wall shelf'                             auto=storage      -> mirror
  FIX FAB486ED 'towel rack'                             auto=ironing board -> none
  BRK 2DCF0F49 'black plastic sheeting / trash bags'    auto=none         -> trash can
  BRK 41B06125 'furniture dolly'                        auto=cart         -> box
  FIX 4426C67D 'furniture dolly'                        auto=mirror       -> cart
  FIX 552B14A6 'clothes rack with hangers'              auto=bed          -> clothes rack
  FIX 6426004E 'rolling step ladder'                    auto=cart         -> ladder
  chg C36C8113 'coat/garment stand base'                auto=lamp         -> cart
  FIX 71E5E585 'furniture dolly'                        auto=box          -> cart

 ('relaxed', 1.0, 3, 'mean-prob', True)
  chg 0DBEFB88 'laptop'                                 auto=mirror       -> television
  FIX 24FFD0F1 'bunk bed ladder + mini fridge'          auto=bag          -> bed
  chg 45269E6D 'floor lamp'                             auto=storage      -> none
  FIX 84C148DA 'laptop'                                 auto=table        -> laptop
  chg DD4F1671 'TV (close-up of screen)'                auto=mirror       -> none
  BRK 431CE7CF 'desk'                                   auto=table        -> storage
  FIX 9728009E 'clothes pile'                           auto=table        -> none
  FIX A4841057 'floor lamp'                             auto=storage      -> lamp
  FIX 1FF89EA4 'backpack on floor'                      auto=suitcase     -> bag
  BRK 6DCEF74F 'trash can'                              auto=trash can    -> toilet
  FIX 8CBF2EE7 'sink'                                   auto=toilet       -> sink
  FIX A52459F5 'open cabinet / nightstand unit'         auto=table        -> storage
  BRK E2DD8E8D 'wall shelf'                             auto=storage      -> none
  FIX FAB486ED 'towel rack'                             auto=ironing board -> none
  BRK 2DCF0F49 'black plastic sheeting / trash bags'    auto=none         -> trash can
  BRK 41B06125 'furniture dolly'                        auto=cart         -> box
  FIX 4426C67D 'furniture dolly'                        auto=mirror       -> cart
  FIX 552B14A6 'clothes rack with hangers'              auto=bed          -> clothes rack
  FIX 6426004E 'rolling step ladder'                    auto=cart         -> ladder
  chg C36C8113 'coat/garment stand base'                auto=lamp         -> cart
  FIX 71E5E585 'furniture dolly'                        auto=box          -> cart

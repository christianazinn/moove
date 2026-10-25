### Classifier alone (argmax class, M3 merges in scoring unless noted)

| Embedding | weights | Public top-1 % | Public top-1 % (no merge) | iPad top-1 % | iPad top-1 % (no merge) | none P % | none R % |
|---|---|---|---|---|---|---|---|
| PyTorch | probe | 83.1 | 80.8 | 67.5 | 63.9 | 100.0 | 53.3 |
| PyTorch | probe + none bias +1 | 82.4 | 80.1 | 67.5 | 63.9 | 87.5 | 70.0 |
| PyTorch | V4 text only | 79.0 | 76.6 | 65.1 | 61.4 | 82.6 | 63.3 |
| CoreML pal8 (Vision) | probe | 83.4 | 80.9 | 65.1 | 61.4 | 100.0 | 56.7 |
| CoreML pal8 (Vision) | probe + none bias +1 | 82.8 | 80.3 | 65.1 | 61.4 | 87.5 | 70.0 |
| CoreML pal8 (Vision) | V4 text only | 78.4 | 76.0 | 61.4 | 57.8 | 79.2 | 63.3 |
| CoreML fp16 (Vision) | probe | 83.3 | 80.7 | 66.3 | 62.7 | 100.0 | 53.3 |
| CoreML fp16 (Vision) | probe + none bias +1 | 82.9 | 80.4 | 66.3 | 62.7 | 84.0 | 70.0 |
| CoreML fp16 (Vision) | V4 text only | 78.6 | 76.0 | 63.9 | 60.2 | 82.6 | 63.3 |

Tuned on public (detector fired, n=912): best score 86.2 at reject 0.6, margin 0.2, oov 0.5; top 5: [(0.862, 0.6, 0.2, 0.5), (0.862, 0.5, 0.2, 0.5), (0.862, 0.4, 0.2, 0.5), (0.862, 0.3, 0.2, 0.5), (0.861, 0.7, 0.2, 0.5)]

### Fused pipeline, iPad split (RoomPlan-origin objects: reject-only at 0.7)

| Pipeline | iPad top-1 % (n=83) | merged (M3) % | none P % | none R % (n=30) | public (detector fired) % |
|---|---|---|---|---|---|
| Recorded scan output | 67.5 | 68.7 | 0.0 | 0.0 | n/a |
| + classifier recheck (size veto: none, none bias +1) | 78.3 | 79.5 | 100.0 | 46.7 | 86.2 |
| + classifier recheck (size veto: none, none bias off) | 77.1 | 78.3 | 100.0 | 26.7 | 86.0 |
| + classifier recheck (size veto: strict, none bias +1) | 69.9 | 71.1 | 100.0 | 36.7 | 86.2 |
| + classifier recheck (size veto: strict, none bias off) | 68.7 | 69.9 | 100.0 | 20.0 | 86.0 |
| + classifier recheck (size veto: loose, none bias +1) | 77.1 | 78.3 | 100.0 | 43.3 | 86.2 |
| + classifier recheck (size veto: loose, none bias off) | 75.9 | 77.1 | 100.0 | 23.3 | 86.0 |
| + classifier recheck (size veto: loose+sure, none bias +1) | 78.3 | 79.5 | 100.0 | 46.7 | 86.2 |
| + classifier recheck (size veto: loose+sure, none bias off) | 77.1 | 78.3 | 100.0 | 26.7 | 86.0 |
| shipped, but RoomPlan objects not rechecked at all | 78.3 | 79.5 | 100.0 | 46.7 | 86.2 |
| same, PyTorch embeddings (loose+sure veto, bias +1) | 80.7 | 81.9 | 100.0 | 50.0 | 85.6 |

Detector objects on iPad: 92; actions: {'keep': 43, 'relabel': 33, 'reject': 14, 'unknown': 2}; RoomPlan objects: 28, actions {'roomplan': 28}

### Hard cases (iPad)

| Photo | Truth | Recorded | Fused | Action | Box W×H×D (m) |
|---|---|---|---|---|---|
| 2026-10-24T07-07-37_3DD1C719 | none (floor mop) | vacuum | vacuum | keep | 0.35×0.07×0.25 |
| 2026-10-24T07-07-37_4389ABCA | none (broom and dustpan) | vacuum | vacuum | keep | 0.28×1.30×0.26 |
| 2026-10-24T07-07-37_CC2F7191 | none (light stand (tripod)) | vacuum | none | reject | 1.28×2.32×0.67 |
| 2026-10-24T07-07-37_ECF24331 | none (light stand (tripod) with sandbag) | vacuum | other | unknown | 1.07×2.08×0.77 |
| 2026-10-24T17-39-03_87E24272 | none (radiator) | heater | laptop | relabel | 0.36×0.64×0.25 |
| 2026-10-24T19-43-54_1162E1D1 | none (radiator) | heater | none | reject | 0.30×0.64×0.20 |
| 2026-10-24T19-43-54_D28DCA97 | none (shower curtain) | room divider | none | reject | 0.53×1.43×0.50 |
| 2026-10-24T21-35-31_1FF89EA4 | backpack (backpack on floor) | vacuum | suitcase | relabel | 0.57×1.05×0.31 |
| 2026-10-24T21-35-31_DDA1762D | none (radiator) | heater | none | reject | 0.26×0.37×0.24 |
| 2026-10-25T02-01-29_4426C67D | cart (furniture dolly) | vacuum | vacuum | keep | 0.40×0.18×0.25 |
| 2026-10-25T02-01-29_644162E4 | box (cardboard box) | bin | box | relabel | 0.88×0.22×0.27 |
| 2026-10-25T02-01-29_72066CED | scooter (e-scooter) | shoe rack | scooter | relabel | 0.70×0.26×0.33 |
| 2026-10-25T02-01-29_AD10D510 | box (cardboard boxes) | bin | box | relabel | 0.95×0.43×0.54 |
| 2026-10-25T02-01-29_B4817201 | ladder (rolling step ladder) | vacuum | ladder | relabel | 0.68×1.10×0.25 |
| 2026-10-25T02-01-29_C36C8113 | coat rack (coat/garment stand base) | vacuum | other | unknown | 0.90×0.60×0.32 |
| 2026-10-25T02-01-29_E7AB5A46 | scooter (e-scooter) | scooter | scooter | keep | 0.88×1.05×0.73 |
| 2026-10-25T02-01-29_E9F85714 | box (cardboard box) | bin | box | relabel | 0.98×0.52×0.47 |
| 2026-10-25T02-05-43_18257B6B | box (cardboard box) | bin | box | relabel | 1.02×0.54×0.36 |
| 2026-10-25T02-05-43_457C4553 | box (cardboard box) | bin | box | relabel | 0.51×0.25×0.38 |
| 2026-10-25T02-05-43_4AADD146 | box (cardboard box) | bin | box | relabel | 0.52×0.50×0.31 |
| 2026-10-25T02-05-43_81686442 | box (cardboard box) | bin | box | relabel | 0.45×0.49×0.29 |
| 2026-10-25T02-05-43_AC5DB808 | scooter (e-scooter) | vacuum | scooter | relabel | 1.00×0.95×0.66 |
| 2026-10-25T02-05-43_F227F60B | unclear (dark flat panel leaning on wall (monitor/board?)) | vacuum | box | relabel | 0.84×0.25×0.25 |

### Every change the recheck made on iPad

| Photo | Truth | Recorded | Fused | Right before → after |
|---|---|---|---|---|
| 2026-10-24T07-05-11_7B501609 | backpack (backpack) | backpack | table | yes → no |
| 2026-10-24T07-07-37_05F7E338 | none (interior window / wall) | refrigerator | none | no → yes |
| 2026-10-24T07-07-37_52CFB458 | none (interior window) | mirror | box | no → no |
| 2026-10-24T07-07-37_9A873C14 | none (blackboard / projection screen on wall) | refrigerator | none | no → yes |
| 2026-10-24T07-07-37_B19EEA1A | bean bag (bean bag) | bean bag | backpack | yes → no |
| 2026-10-24T07-07-37_CC2F7191 | none (light stand (tripod)) | vacuum | none | no → yes |
| 2026-10-24T07-07-37_ECF24331 | none (light stand (tripod) with sandbag) | vacuum | other | no → no |
| 2026-10-24T17-39-03_0DBEFB88 | laptop (laptop) | laptop | box | yes → no |
| 2026-10-24T17-39-03_87E24272 | none (radiator) | heater | laptop | no → no |
| 2026-10-24T17-39-03_D048193B | bed (bed (corner)) | laptop | bed | no → yes |
| 2026-10-24T17-39-03_EBDCE727 | unclear (dark object on floor (bag?)) | bag | plant | no → no |
| 2026-10-24T17-56-45_24FFD0F1 | bed (bunk bed ladder + mini fridge) | ladder | stroller | no → no |
| 2026-10-24T17-56-45_45269E6D | lamp (floor lamp) | lamp | storage | yes → no |
| 2026-10-24T17-56-45_72E3E565 | television (wall-mounted TV) | none | television | no → yes |
| 2026-10-24T19-43-54_02F7BF6A | none (towel rack) | workbench | none | no → yes |
| 2026-10-24T19-43-54_1162E1D1 | none (radiator) | heater | none | no → yes |
| 2026-10-24T19-43-54_A4841057 | lamp (floor lamp) | lamp | storage | yes → no |
| 2026-10-24T19-43-54_AEA164D9 | none (towel rack / shower wall) | humidifier | none | no → yes |
| 2026-10-24T19-43-54_D28DCA97 | none (shower curtain) | room divider | none | no → yes |
| 2026-10-24T19-43-54_FD6CD8DF | bed (bed) | other | bed | no → yes |
| 2026-10-24T21-35-31_1FF89EA4 | backpack (backpack on floor) | vacuum | suitcase | no → no |
| 2026-10-24T21-35-31_20327CC7 | none (towel rack) | humidifier | none | no → yes |
| 2026-10-24T21-35-31_655BE7AB | chair (office chair (partial)) | other | bed | no → no |
| 2026-10-24T21-35-31_C87A696A | none (doorway) | storage | mirror | no → no |
| 2026-10-24T21-35-31_CE53F088 | none (door) | storage | none | no → yes |
| 2026-10-24T21-35-31_DDA1762D | none (radiator) | heater | none | no → yes |
| 2026-10-25T02-01-29_2C3C0F81 | clothes rack (clothes rack with hangers) | sewing machine | ironing board | no → no |
| 2026-10-25T02-01-29_2DCF0F49 | none (black plastic sheeting / trash bags) | bean bag | none | no → yes |
| 2026-10-25T02-01-29_41B06125 | cart (furniture dolly) | yoga mat | cart | no → yes |
| 2026-10-25T02-01-29_552B14A6 | clothes rack (clothes rack with hangers) | crib | bed | no → no |
| 2026-10-25T02-01-29_6426004E | ladder (rolling step ladder) | chair | cart | no → no |
| 2026-10-25T02-01-29_644162E4 | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-01-29_72066CED | scooter (e-scooter) | shoe rack | scooter | no → yes |
| 2026-10-25T02-01-29_80EAEC37 | clothes rack (wire garment rack (+ step ladder)) | room divider | ladder | no → no |
| 2026-10-25T02-01-29_912FC200 | unclear (clutter: boards, step ladder) | refrigerator | cart | no → no |
| 2026-10-25T02-01-29_AD10D510 | box (cardboard boxes) | bin | box | no → yes |
| 2026-10-25T02-01-29_B4817201 | ladder (rolling step ladder) | vacuum | ladder | no → yes |
| 2026-10-25T02-01-29_C36C8113 | coat rack (coat/garment stand base) | vacuum | other | no → no |
| 2026-10-25T02-01-29_E9F85714 | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-05-43_02A716D2 | none (structural pole) | room divider | none | no → yes |
| 2026-10-25T02-05-43_18257B6B | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-05-43_457C4553 | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-05-43_4A00F91C | none (black plastic sheeting / trash bags) | bag | none | no → yes |
| 2026-10-25T02-05-43_4AADD146 | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-05-43_71E5E585 | cart (furniture dolly) | yoga mat | box | no → no |
| 2026-10-25T02-05-43_81686442 | box (cardboard box) | bin | box | no → yes |
| 2026-10-25T02-05-43_AC5DB808 | scooter (e-scooter) | vacuum | scooter | no → yes |
| 2026-10-25T02-05-43_F227F60B | unclear (dark flat panel leaning on wall (monitor/board?)) | vacuum | box | no → no |
| 2026-10-25T02-05-43_FF8CA209 | none (black plastic sheeting) | workbench | none | no → yes |
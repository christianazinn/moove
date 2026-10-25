### A. Leave-one-scan-out with own iPad photos (prompt set V4; iPad rows only; 10 scans)

| Method | public shots/class | iPad weight | iPad top-1 % | none P % | none R % |
|---|---|---|---|---|---|
| PROBE 1.0 | 0 | 1 | 68.7 | 87.0 | 66.7 |
| PROBE 1.0 | 0 | 3 | 68.7 | 83.3 | 66.7 |
| PROBE 1.0 | 1 | 1 | 68.7 | 79.2 | 63.3 |
| PROBE 1.0 | 1 | 3 | 67.5 | 82.6 | 63.3 |
| PROBE 1.0 | 4 | 1 | 66.3 | 79.2 | 63.3 |
| PROBE 1.0 | 4 | 3 | 71.1 | 82.6 | 63.3 |
| PROBE 1.0 | all | 1 | 66.3 | 95.0 | 63.3 |
| PROBE 1.0 | all | 3 | 65.1 | 89.5 | 56.7 |
| PROBE 0.1 | 0 | 1 | 71.1 | 90.9 | 66.7 |
| PROBE 0.1 | 0 | 3 | 71.1 | 90.9 | 66.7 |
| PROBE 0.1 | 1 | 1 | 72.3 | 90.5 | 63.3 |
| PROBE 0.1 | 1 | 3 | 72.3 | 90.5 | 63.3 |
| PROBE 0.1 | 4 | 1 | 69.9 | 81.8 | 60.0 |
| PROBE 0.1 | 4 | 3 | 71.1 | 82.6 | 63.3 |
| PROBE 0.1 | all | 1 | 66.3 | 77.3 | 56.7 |
| PROBE 0.1 | all | 3 | 69.9 | 77.3 | 56.7 |
| PROBE 0.01 | 0 | 1 | 71.1 | 86.4 | 63.3 |
| PROBE 0.01 | 0 | 3 | 71.1 | 86.4 | 63.3 |
| PROBE 0.01 | 1 | 1 | 73.5 | 82.6 | 63.3 |
| PROBE 0.01 | 1 | 3 | 73.5 | 82.6 | 63.3 |
| PROBE 0.01 | 4 | 1 | 73.5 | 86.4 | 63.3 |
| PROBE 0.01 | 4 | 3 | 72.3 | 81.8 | 60.0 |
| PROBE 0.01 | all | 1 | 69.9 | 81.8 | 60.0 |
| PROBE 0.01 | all | 3 | 69.9 | 78.3 | 60.0 |
| PROTO 0.6 | 0 | 1 | 68.7 | 66.7 | 60.0 |
| PROTO 0.6 | 1 | 1 | 68.7 | 64.5 | 66.7 |
| PROTO 0.6 | 4 | 1 | 66.3 | 63.3 | 63.3 |
| PROTO 0.6 | all | 1 | 54.2 | 52.8 | 63.3 |
| TIP (1, 10) | 0 | 1 | 63.9 | 90.9 | 66.7 |
| TIP (1, 10) | 1 | 1 | 63.9 | 90.9 | 66.7 |
| TIP (1, 10) | 4 | 1 | 63.9 | 90.9 | 66.7 |
| TIP (1, 10) | all | 1 | 63.9 | 94.4 | 56.7 |

### B. none-bias chosen per held-out scan on the other scans (iPad only)

| Model | iPad top-1 % | none P % | none R % | biases chosen |
|---|---|---|---|---|
| ZS V4 | 60.2 | 71.4 | 66.7 | [(np.float64(-0.5), 1), (np.float64(1.0), 2), (np.float64(1.5), 7)] |
| PROBE lam=1, public only | 63.9 | 87.5 | 70.0 | [(np.float64(1.0), 10)] |
| PROBE lam=1, public all + LOSO iPad | 65.1 | 79.2 | 63.3 | [(np.float64(0.0), 8), (np.float64(0.5), 1), (np.float64(1.5), 1)] |
| PROBE lam=0.1, public k=1 + LOSO iPad | 69.9 | 75.0 | 60.0 | [(np.float64(-1.5), 1), (np.float64(-1.0), 5), (np.float64(-0.5), 1), (np.float64(1.5), 3)] |
| PROBE lam=0.1, public all + LOSO iPad x3 | 67.5 | 70.8 | 56.7 | [(np.float64(-1.5), 2), (np.float64(0.5), 1), (np.float64(1.0), 7)] |

### C. Label merges (both truth and prediction mapped; public = ZS / 5-fold probe, iPad as stated)

| Merge | V0 ZS pub | V0 ZS iPad | V4 ZS pub | V4 ZS iPad | probe(lam=1) pub CV | probe iPad | LOSO probe iPad |
|---|---|---|---|---|---|---|---|
| none | 76.2 | 62.7 | 76.6 | 61.4 | 80.9 | 63.9 | 72.3 |
| M1 bag+backpack | 77.5 | 65.1 | 77.7 | 63.9 | 81.9 | 66.3 | 77.1 |
| M2 M1 + TV+monitor=screen | 78.0 | 65.1 | 78.2 | 63.9 | 82.4 | 66.3 | 77.1 |
| M3 M2 + shelf->storage | 78.9 | 66.3 | 79.0 | 65.1 | 83.1 | 67.5 | 77.1 |
| M4 M3 + suitcase->bag | 79.5 | 67.5 | 79.5 | 66.3 | 83.7 | 68.7 | 77.1 |

### D. iPad geometry for table / storage / shelf / chair (and anything predicted as one)

| photo | truth | object | box W x H x D (m) | V0 ZS | V4 ZS | 2nd choice V4 |
|---|---|---|---|---|---|---|
| 2026-10-24T03-57-34_74BF85B7 | storage | sink base cabinet | 1.64x0.96x0.69 | sink | sink | storage |
| 2026-10-24T07-05-11_6130EBF7 | chair | folding chair | 0.86x0.05x0.20 | chair | chair | table |
| 2026-10-24T07-05-11_7B501609 | backpack | backpack | 0.25x0.09x0.16 | table | table | chair |
| 2026-10-24T07-07-37_8E360936 | storage | sink base cabinet | 1.62x0.96x0.69 | sink | sink | storage |
| 2026-10-24T08-53-59_0CC27606 | storage | cabinet holding microwave + mi | 0.67x1.01x0.58 | refrigerator | refrigerator | microwave |
| 2026-10-24T08-53-59_5D88AEAE | table | desk | 1.01x0.83x0.63 | storage | storage | bag |
| 2026-10-24T08-53-59_A625D0FE | ottoman | ottoman / cube stool | 0.55x1.13x0.64 | storage | storage | bed |
| 2026-10-24T08-53-59_D9D5E421 | bed | bed | 1.75x0.58x2.15 | storage | storage | bed |
| 2026-10-24T17-39-03_0CE28DD6 | unclear | unclear dark corner | 0.36x0.44x0.17 | storage | storage | none |
| 2026-10-24T17-39-03_60BFD08C | none | clothes pile | 0.35x0.16x0.19 | table | table | bathtub |
| 2026-10-24T17-39-03_DFFD405C | chair | office chair | 0.45x0.87x0.51 | chair | chair | ottoman |
| 2026-10-24T17-56-45_12747CDA | chair | office chair | 0.51x0.86x0.60 | chair | chair | ironing board |
| 2026-10-24T17-56-45_2A2E7826 | storage | cabinet holding microwave + mi | 1.87x1.42x0.68 | refrigerator | refrigerator | microwave |
| 2026-10-24T17-56-45_45269E6D | lamp | floor lamp | 0.26x0.73x0.25 | storage | storage | lamp |
| 2026-10-24T19-43-54_431CE7CF | table | desk | 1.02x0.83x0.60 | table | table | storage |
| 2026-10-24T19-43-54_69623E38 | storage | open cabinet / nightstand unit | 0.67x1.48x0.59 | storage | storage | table |
| 2026-10-24T19-43-54_8DE6477F | shelf | wall shelf | 0.45x0.24x0.17 | toilet | toilet | shelf |
| 2026-10-24T19-43-54_9728009E | none | clothes pile | 0.35x0.16x0.27 | storage | storage | mirror |
| 2026-10-24T19-43-54_A4841057 | lamp | floor lamp | 0.31x0.90x0.25 | storage | storage | lamp |
| 2026-10-24T19-43-54_C702EE67 | chair | office chair | 0.58x0.99x0.62 | chair | chair | backpack |
| 2026-10-24T19-43-54_FD6CD8DF | bed | bed | 0.59x0.78x0.52 | storage | storage | bed |
| 2026-10-24T21-35-31_5DC86A38 | chair | office chair | 0.50x0.98x0.60 | none | none | stroller |
| 2026-10-24T21-35-31_655BE7AB | chair | office chair (partial) | 0.57x0.62x0.18 | bed | bed | stroller |
| 2026-10-24T21-35-31_A52459F5 | storage | open cabinet / nightstand unit | 0.68x1.43x0.57 | storage | storage | table |
| 2026-10-24T21-35-31_E2DD8E8D | shelf | wall shelf | 0.45x0.21x0.15 | storage | storage | toilet |
| 2026-10-24T21-35-31_E7BD1FAC | table | desk | 0.92x0.81x0.62 | table | table | storage |

Height rule (table vs storage, only when those are the top-2 labels):

| Model | before iPad % | after iPad % | changed photos |
|---|---|---|---|
| V4 ZS | 61.4 | 61.4 | [] |
| LOSO probe | 72.3 | 73.5 | [('storage', 'table', 'storage')] |

### Prompt variants (PE-Core-S/16-384, saved image embeddings, logit scale 100)

| Variant | Public top-1 % | iPad top-1 % (n=83) | none P % | none R % (n=30) |
|---|---|---|---|---|
| V0 baseline (zs_eval.py prompts) (57 cls) | 76.2 | 62.7 | 89.5 | 56.7 |
| V0a baseline, 1 template (57 cls) | 75.8 | 59.0 | 85.7 | 60.0 |
| V0b baseline, 8 templates (57 cls) | 76.3 | 61.4 | 94.4 | 56.7 |
| V1 synonyms (57 cls) | 76.4 | 60.2 | 84.2 | 53.3 |
| V1b synonyms, 8 templates (57 cls) | 76.2 | 59.0 | 94.4 | 56.7 |
| V2 brief negatives (62 cls) | 75.8 | 61.4 | 82.6 | 63.3 |
| V2b brief + generic negatives (65 cls) | 75.4 | 59.0 | 75.9 | 73.3 |
| V2c brief + generic + iPad-informed negatives (70 cls) | 75.2 | 59.0 | 77.4 | 80.0 |
| V3 synonyms + brief negatives (62 cls) | 76.0 | 57.8 | 75.0 | 60.0 |
| V3b synonyms + brief + generic negatives (65 cls) | 75.6 | 55.4 | 72.4 | 70.0 |
| V3c synonyms + brief + generic + iPad-informed neg (70 cls) | 75.5 | 55.4 | 75.0 | 80.0 |
| V3d = V3b, 8 templates (65 cls) | 75.6 | 55.4 | 77.8 | 70.0 |

### One-class synonym ablation on top of V2b (delta vs V2b, pp)

| class changed | public | iPad | none P | none R |
|---|---|---|---|---|
| backpack | +0.0 | +0.0 | +0.0 | +0.0 |
| bag | -0.1 | +0.0 | +0.0 | +0.0 |
| table | +0.0 | +0.0 | +0.0 | +0.0 |
| desk | -0.1 | +0.0 | +0.0 | +0.0 |
| bookshelf | +0.0 | +0.0 | +0.0 | +0.0 |
| shelf | +0.2 | +0.0 | +0.0 | +0.0 |
| cabinet | +0.2 | +0.0 | +0.0 | +0.0 |
| nightstand | +0.0 | +0.0 | +0.0 | +0.0 |
| chair | -0.1 | +0.0 | +0.0 | +0.0 |
| monitor | -0.1 | +0.0 | +0.0 | +0.0 |
| television | +0.0 | +0.0 | +0.0 | +0.0 |
| mirror | +0.1 | +0.0 | +0.0 | +0.0 |
| trash_can | +0.1 | -1.2 | -2.5 | +0.0 |
| sink | +0.0 | +0.0 | +0.0 | +0.0 |
| rug | +0.1 | +0.0 | +0.0 | +0.0 |
| box | -0.1 | +0.0 | +0.0 | +0.0 |
| dolly_cart | +0.0 | +0.0 | -0.9 | -3.3 |
| heater | +0.1 | +0.0 | +0.0 | +0.0 |
| sofa | +0.1 | +0.0 | +0.0 | +0.0 |
| plant | +0.1 | +0.0 | +0.0 | +0.0 |
| ottoman | -0.2 | +0.0 | +0.0 | +0.0 |
| suitcase | -0.1 | -1.2 | +0.0 | +0.0 |
| lamp | +0.1 | +0.0 | +0.0 | +0.0 |

### Confusions

- **V0 baseline (zs_eval.py prompts)** public: bag->backpack 21; table->storage 13; shelf->storage 13; storage->table 11; chair->table 10; shower curtain->none 7
  - iPad: storage->sink 2; none->box 2; storage->refrigerator 2; bed->storage 2; lamp->storage 2; bag->backpack 2
- **V3b synonyms + brief + generic negatives** public: bag->backpack 17; table->storage 11; storage->table 10; chair->table 9; bag->suitcase 9; cart->suitcase 9
  - iPad: storage->sink 2; chair->none 2; none->cart 2; storage->refrigerator 2; table->storage 2; bed->storage 2

### none-bias sweep on V3b (b added to every `none` prompt logit; positive = more rejection)

| Variant | Public top-1 % | iPad top-1 % (n=83) | none P % | none R % (n=30) |
|---|---|---|---|---|
| b=-2 | 77.0 | 59.0 | 86.7 | 43.3 |
| b=-1 | 76.7 | 59.0 | 88.9 | 53.3 |
| b=+0 | 75.6 | 55.4 | 72.4 | 70.0 |
| b=+1 | 74.2 | 54.2 | 73.5 | 83.3 |
| b=+2 | 71.5 | 50.6 | 61.9 | 86.7 |
| b=+3 | 68.5 | 43.4 | 51.9 | 93.3 |
| b=+4 | 62.6 | 36.1 | 43.1 | 93.3 |
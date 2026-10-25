LORO-chosen biases: Counter({np.float64(1.0): 5, np.float64(3.0): 1})
| Recipe | merge | Public top-1 % | iPad top-1 % | none P % | none R % |
|---|---|---|---|---|---|
| V0 ZS (current) | none | 76.2 | 62.7 | 89.5 | 56.7 |
| V0 ZS (current) | M1 bag+backpack | 77.5 | 65.1 | 89.5 | 56.7 |
| V0 ZS (current) | M3 M2 + shelf->storage | 78.9 | 66.3 | 89.5 | 56.7 |
| V4 ZS | none | 76.6 | 61.4 | 82.6 | 63.3 |
| V4 ZS | M1 bag+backpack | 77.7 | 63.9 | 82.6 | 63.3 |
| V4 ZS | M3 M2 + shelf->storage | 79.0 | 65.1 | 82.6 | 63.3 |
| V4 + probe lam=1 | none | 80.9 | 63.9 | 100.0 | 53.3 |
| V4 + probe lam=1 | M1 bag+backpack | 81.9 | 66.3 | 100.0 | 53.3 |
| V4 + probe lam=1 | M3 M2 + shelf->storage | 83.1 | 67.5 | 100.0 | 53.3 |
| V4 + probe lam=1 + none bias +1 | none | 80.2 | 63.9 | 87.5 | 70.0 |
| V4 + probe lam=1 + none bias +1 | M1 bag+backpack | 81.3 | 66.3 | 87.5 | 70.0 |
| V4 + probe lam=1 + none bias +1 | M3 M2 + shelf->storage | 82.4 | 67.5 | 87.5 | 70.0 |

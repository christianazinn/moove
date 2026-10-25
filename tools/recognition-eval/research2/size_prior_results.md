### E. Size prior on iPad (penalty lam per log-unit of size violation)

| Model | lam | iPad top-1 % | none P % | none R % | M3-merged iPad % |
|---|---|---|---|---|---|
| V0 ZS | 0 | 62.7 | 89.5 | 56.7 | 66.3 |
| V0 ZS | 1 | 60.2 | 89.5 | 56.7 | 63.9 |
| V0 ZS | 2 | 61.4 | 89.5 | 56.7 | 65.1 |
| V0 ZS | 4 | 62.7 | 90.0 | 60.0 | 65.1 |
| V0 ZS | 8 | 66.3 | 90.0 | 60.0 | 68.7 |
| V4 ZS | 0 | 61.4 | 82.6 | 63.3 | 65.1 |
| V4 ZS | 1 | 59.0 | 82.6 | 63.3 | 62.7 |
| V4 ZS | 2 | 61.4 | 82.6 | 63.3 | 65.1 |
| V4 ZS | 4 | 62.7 | 82.6 | 63.3 | 65.1 |
| V4 ZS | 8 | 63.9 | 82.6 | 63.3 | 66.3 |
| LOSO probe lam=0.1 k=1 | 0 | 72.3 | 90.5 | 63.3 | 77.1 |
| LOSO probe lam=0.1 k=1 | 1 | 73.5 | 90.5 | 63.3 | 78.3 |
| LOSO probe lam=0.1 k=1 | 2 | 72.3 | 86.4 | 63.3 | 77.1 |
| LOSO probe lam=0.1 k=1 | 4 | 71.1 | 82.6 | 63.3 | 74.7 |
| LOSO probe lam=0.1 k=1 | 8 | 68.7 | 76.9 | 66.7 | 72.3 |

V4 ZS changes at lam=4 (truth: before -> after): storage: sink->storage; chair: chair->mirror; backpack: table->laptop; unclear: box->none; none: box->table; storage: sink->storage; none: table->sink; bed: bed->storage; bed: suitcase->stroller; trash can: toilet->sink; shelf: toilet->shelf; none: storage->mirror; chair: bed->stroller; laptop: laptop->table; sink: toilet->sink; shelf: storage->suitcase; clothes rack: bed->ironing board

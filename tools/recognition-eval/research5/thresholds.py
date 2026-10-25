"""Label-level threshold search (coordinate descent, objective = public top-1 incl. 'none') on top of the mapping
proposal, with 5-fold CV grouped by source photo. Only labels whose category is a bench target are tuned; never
below the current threshold minus 0.05 (we want fewer FPs, not more recall noise)."""
import sys, json; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
GRID = [round(x, 2) for x in np.arange(0.25, 0.96, 0.05)]
TARGETS = set(tgt(truth(r)) for r in PUB) - {"none"}
def acc(cfg, rs): return sum(t == p for t, p in single(cfg, rs))
def search(rs, base_lminc=None, rounds=2):
    cfg = cfg_map("tuned", lminc=dict(base_lminc or {}))
    labs = [l for l, c in cfg.cat.items() if c in TARGETS]
    for _ in range(rounds):
        for l in labs:
            cur = cfg.thr(l, cfg.cat[l]); best = (acc(cfg, rs), -abs(0), cur)
            for t in GRID:
                if t < cur - 0.051 and t < cfg.minc.get(cfg.cat[l], cfg.defc) - 0.051: continue
                cfg.lminc[l] = t; a = acc(cfg, rs)
                if a > best[0] or (a == best[0] and t > best[2]): best = (a, 0, t)
            cfg.lminc[l] = best[2]
    return {l: t for l, t in cfg.lminc.items() if abs(t - cfg.minc.get(cfg.cat[l], cfg.defc)) > 1e-6 or True}
def group(r): b = r["path"].split("/")[-1][:-4]; return "_".join(b.split("_")[:2])
if __name__ == "__main__":
    full = search(PUB)
    json.dump(full, open("/tmp/claude-501/eval/research5/tuned_lminc.json", "w"), indent=1)
    g = sorted(set(group(r) for r in PUB)); rng = np.random.default_rng(0); rng.shuffle(g)
    fold = {x: i % 5 for i, x in enumerate(g)}
    base = cfg_map(); pc = pt = pb = 0
    for k in range(5):
        tr = [r for r in PUB if fold[group(r)] != k]; te = [r for r in PUB if fold[group(r)] == k]
        lm = search(tr, rounds=1)
        pc += acc(cfg_map(lminc=lm), te); pb += acc(base, te); pt += len(te)
    print(f"public CV top-1: mapping only {100*pb/pt:.1f}  mapping+tuned thresholds {100*pc/pt:.1f}  (in-sample tuned {100*acc(cfg_map(lminc=full), PUB)/len(PUB):.1f})")
    cur = cfg_map()
    for l, t in sorted(full.items()):
        c = cur.thr(l, cur.cat[l])
        if abs(t - c) > 1e-6: print(f"  {l:24s} {cur.cat[l]:14s} {c:.2f} -> {t:.2f}")

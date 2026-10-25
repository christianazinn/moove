"""Paired significance for the main iPad comparison + how many own (iPad) photos the LOSO probe needs."""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research2")
from fewshot2 import *
names, labels, W0, Cd = text_set("V4")
y = row_class(names, labels, W0); C = len(labels); ip = np.where(is_ipad)[0]
base = Z["labels"][Z["logits"].argmax(1)].astype(object)
L = loso_logits("PROBE", 0.1, W0, y, C, 1, np.random.default_rng(7))
lp = base.copy(); lp[ip] = labels[L[ip].argmax(1)]
ok0 = np.array([ipad_view(p) == canon(g) for p, g in zip(base, gt)]); ok1 = np.array([ipad_view(p) == canon(g) for p, g in zip(lp, gt)])
m = ipad_obj
b, c = (ok1 & ~ok0 & m).sum(), (ok0 & ~ok1 & m).sum()
from math import comb
pval = min(1, 2 * sum(comb(b + c, i) for i in range(0, min(b, c) + 1)) / 2 ** (b + c))
print(f"iPad objects: V0 ZS right {ok0[m].sum()}/83, LOSO probe right {ok1[m].sum()}/83; fixed {b}, broken {c}; exact McNemar p={pval:.3f}")
rng = np.random.default_rng(0); oi = np.where(m)[0]
bs = [np.mean(ok1[s]) - np.mean(ok0[s]) for s in (rng.choice(oi, len(oi)) for _ in range(2000))]
print("bootstrap 95% CI of gain (pp):", np.percentile(bs, [2.5, 97.5]) * 100)
print("remaining LOSO-probe iPad confusions:", collections.Counter((gt[i], ipad_view(lp[i])) for i in ip if gt[i] != "unclear" and ipad_view(lp[i]) != canon(gt[i])).most_common(12))
# own-photo budget: keep a fraction of the other scans' iPad photos
print("| fraction of other-scan iPad photos kept | approx photos in train | iPad top-1 % | none P | none R |\n|---|---|---|---|---|")
for frac in (0.0, 0.25, 0.5, 0.75, 1.0):
    accs = []
    for s in range(5 if 0 < frac < 1 else 1):
        r = np.random.default_rng(s); p = base.copy(); trp = sample(pub_idx, y, 1, np.random.default_rng(7))
        for sc in np.unique(scan[ip]):
            te = ip[scan[ip] == sc]; tri = ip[(scan[ip] != sc) & (y[ip] >= 0)]
            tri = r.choice(tri, int(round(frac * len(tri))), replace=False) if frac < 1 else tri
            p[te] = labels[run_method("PROBE", 0.1, W0, np.concatenate([trp, tri]).astype(int), te, y, C).argmax(1)]
        mm = metrics(p); accs.append((mm["ipad"], mm["nP"], mm["nR"]))
    a = np.mean(accs, 0)
    print(f"| {frac} | ~{int(frac * 101)} | {100*a[0]:.1f} | {100*a[1]:.1f} | {100*a[2]:.1f} |")

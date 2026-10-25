"""Guard against picking the best of ~150 configs on n=70: (a) leave-one-scan-out config selection,
(b) paired bootstrap / sign test for a few pre-specified configs vs the auto photo. Appends to mv_results.md."""
import sys, os, io, contextlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
with contextlib.redirect_stdout(io.StringIO()):
    import mv_eval as E
import numpy as np
from math import comb

rows, truth, real, isnone, scored = E.rows, E.truth, E.real, E.isnone, E.scored
scan = np.array([r["scan"] for r in rows]); base = E.base[3]
def objective(pred, m):  # top-1 on real + none F1-ish: simple sum of top-1 and none recall/precision avg
    t = np.mean(pred[m & real] == truth[m & real]) if (m & real).any() else 0
    return t

out = []; w = out.append
w("\n## Leave-one-scan-out config selection (pick best top-1 config on 5 scans, score on the 6th)\n")
picked = np.empty(len(rows), dtype=object); chosen = []
for s in np.unique(scan):
    tr = scan != s
    best = max(E.results, key=lambda k: (objective(E.results[k], tr), -len(str(k))))
    chosen.append((s[-8:], best)); picked[~tr] = E.results[best][~tr]
t, p, r, _ = E.evaluate(picked)
w(f"LOSO-selected multi-view: top-1 {100*t:.1f}%, none P {100*p:.1f}%, none R {100*r:.1f}%  (auto photo: {100*E.base[0]:.1f} / {100*E.base[1]:.1f} / {100*E.base[2]:.1f})")
w("Configs chosen per held-out scan: " + "; ".join(f"{s}: {k}" for s, k in chosen))

w("\n## Paired comparison vs auto photo on real objects (n=70): fixed / broken, exact sign-test p, bootstrap 95% CI of delta top-1\n")
w("| config | top-1 % | fixed | broken | sign p | delta CI (pts) |\n|---|---|---|---|---|---|")
rng = np.random.default_rng(0); idx = np.where(real)[0]
for k in [("strict", 1.0, 1, "mean-emb", False), ("strict", 1.0, 3, "max-conf", True), ("relaxed", 1.0, 3, "max-conf", True),
          ("relaxed", 1.0, 3, "vote", True), ("relaxed", 1.0, 3, "mean-prob", True), ("strict", 1.3, "all", "mean-emb", True),
          ("relaxed", 1.3, 5, "mean-prob", True), ("strict", 1.6, "all", "mean-prob", True)]:
    pr = E.results[k]; a = (pr[idx] == truth[idx]).astype(int); b = (base[idx] == truth[idx]).astype(int)
    fx, br = int(((a == 1) & (b == 0)).sum()), int(((a == 0) & (b == 1)).sum()); n = fx + br
    pv = min(1, 2 * sum(comb(n, i) for i in range(min(fx, br) + 1)) / 2 ** n) if n else 1
    d = [100 * (a[s].mean() - b[s].mean()) for s in (rng.integers(0, len(idx), len(idx)) for _ in range(5000))]
    w(f"| {k} | {100*a.mean():.1f} | {fx} | {br} | {pv:.2f} | [{np.percentile(d, 2.5):+.1f}, {np.percentile(d, 97.5):+.1f}] |")
open(f"{E.HERE}/mv_results.md", "a").write("\n".join(out) + "\n")
print("\n".join(out))

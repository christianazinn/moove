"""Per truth class: which labels fire on the main object (box area >= 0.15), with max scores."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from common import *
want = sys.argv[1:] or None
by = collections.defaultdict(lambda: collections.defaultdict(list))
ntr = collections.Counter()
for r in rows:
    t = r["label"] if r["split"] == "public" else "ipad:" + (r["true_object"] if r["label"] in ("none","unclear") else r["label"])
    ntr[t] += 1
    best = {}
    for lab, s, b in raw[r["path"]]["det"]:
        if b[2] * b[3] >= 0.15: best[lab] = max(best.get(lab, 0), s)
    for lab, s in best.items(): by[t][lab].append(s)
for t in sorted(by):
    if want and not any(w in t for w in want): continue
    items = sorted(by[t].items(), key=lambda kv: -len(kv[1]))[:8]
    print(f"{t} (n={ntr[t]}): " + "; ".join(f"{l}[{CAT.get(l,'-')}] {len(v)}x med{np.median(v):.2f} max{max(v):.2f}" for l, v in items))

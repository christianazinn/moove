"""Per detector label: which truth classes it fires on (public crops + iPad photos), main-object boxes only."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from common import *
MINAREA = float(sys.argv[1]) if len(sys.argv) > 1 else 0.15
MINS = float(sys.argv[2]) if len(sys.argv) > 2 else 0.2
for split in ("public", "ipad"):
    conf = collections.defaultdict(collections.Counter)
    for r in rows:
        if r["split"] != split: continue
        best = {}
        for lab, s, b in raw[r["path"]]["det"]:
            if b[2] * b[3] >= MINAREA and s >= MINS: best[lab] = max(best.get(lab, 0), s)
        for lab in best: conf[lab][r["label"] if split == "public" else r["label"] + ("" if r["label"] != "none" else ":" + r["true_object"][:18])] += 1
    print(f"\n## {split} (box area >= {MINAREA}, score >= {MINS})")
    for lab, c in sorted(conf.items(), key=lambda kv: -sum(kv[1].values())):
        cat = CAT.get(lab, "-"); n = sum(c.values()); ok = sum(v for k, v in c.items() if CANON.get(k, k) == cat)
        print(f"{lab:24s} -> {cat:14s} n={n:3d} ok={ok:3d}  " + ", ".join(f"{k}:{v}" for k, v in c.most_common(6)))

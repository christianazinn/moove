import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from sim import *
T = collections.defaultdict(collections.Counter)
for r in REC:
    t = r["label"] if r["label"] not in ("none",) else "none:" + r["true_object"][:24]
    T[r["detector_label"]][t] += 1
for rc, c in sorted(T.items(), key=lambda kv: -sum(kv[1].values())):
    ok = c.get(rc, 0) + (c.get("ceiling fan", 0) if rc == "fan" else 0)
    print(f"{str(rc):14s} n={sum(c.values()):2d} right={ok:2d} | " + ", ".join(f"{k}:{v}" for k, v in c.most_common()))

"""Per label on full keyframes: matched objects' truths (distinct objects, frames), scores."""
import sys, json, collections; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from common import CAT, MINC, DEFC, CANON
A = [json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_assoc.jsonl")]
print("min score in raw:", min(a["score"] for a in A))
lab = collections.defaultdict(lambda: collections.defaultdict(list))
for a in A:
    if "obj" not in a: continue
    t = a["truth"] if a["truth"] not in ("none", "unclear") else a["truth"] + ":" + a["true_object"][:22]
    lab[a["label"]][t].append(round(a["score"], 2))
for l, d in sorted(lab.items(), key=lambda kv: -sum(len(v) for v in kv[1].values())):
    c = CAT.get(l, "-"); th = MINC.get(c, DEFC)
    print(f"{l:22s}[{c}, thr {th}] " + "; ".join(f"{t}: {len(v)}fr max{max(v)} pass{sum(s>=th for s in v)}" for t, v in sorted(d.items(), key=lambda kv: -len(kv[1]))))

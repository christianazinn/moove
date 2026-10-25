"""Per label: scores when it is the app's pick (current thresholds ignored: best detection overall >= 0.25)
split into right/wrong vs truth, public and iPad photos; plus full-frame matched sightings."""
import sys, json; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from common import *
def q(v): return "-" if not v else f"{len(v)}: " + "/".join(f"{x:.2f}" for x in np.percentile(v, [10, 50, 90]))
S = collections.defaultdict(lambda: collections.defaultdict(list))
for r in rows:
    t = truth(r)
    if t == "unclear": continue
    # per label: its best main-ish box (area >= 0.05) in this crop
    best = {}
    for lab, s, b in raw[r["path"]]["det"]:
        if b[2]*b[3] >= 0.05: best[lab] = max(best.get(lab, 0), s)
    for lab, s in best.items():
        ok = CANON.get(CAT.get(lab), CAT.get(lab)) == t
        S[lab][(r["split"], ok)].append(s)
for a in (json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_assoc.jsonl")):
    if "obj" not in a or a["truth"] == "unclear": continue
    t = "none" if a["truth"] in FIXTURE else a["truth"]
    S[a["label"]][("frames", CAT.get(a["label"]) == t)].append(a["score"])
print(f"{'label':24s} {'cat':12s} thr | public right n:p10/p50/p90 | public wrong | ipad right | ipad wrong | frames right | frames wrong")
for lab in sorted(S, key=lambda l: -sum(len(v) for v in S[l].values())):
    c = CAT.get(lab, "-")
    print(f"{lab:24s} {c:12s} {MINC.get(c, DEFC):.2f} | " + " | ".join(q(S[lab][(sp, ok)]) for sp in ("public", "ipad", "frames") for ok in (True, False)))

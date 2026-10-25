"""Labels whose category has no truth class in the bench: wrong firings (public+iPad photos main box, keyframe sightings)
kept at current vs proposed threshold. Recall cannot be measured; for reference the pooled score distribution of
CORRECT firings of bench-supported labels."""
import sys, json; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
P = cfg_map(lminc=LMINC); C = Cfg("cur")
TARGETS = set(tgt(truth(r)) for r in rows if r["label"] != "unclear") - {"none"}
W = collections.defaultdict(list); OK = []
for r in rows:
    if r["label"] == "unclear": continue
    t = tgt(truth(r)); best = {}
    for lab, s, b in raw[r["path"]]["det"]:
        if b[2]*b[3] >= 0.05: best[lab] = max(best.get(lab, 0), s)
    for lab, s in best.items():
        c = CAT.get(lab)
        if c in TARGETS and c == t: OK.append(s)
        if c not in TARGETS: W[lab].append(s)
for a in (json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_assoc.jsonl")):
    if "obj" in a and CAT.get(a["label"]) not in TARGETS: W[a["label"]].append(a["score"])
OK = np.array(OK)
print("pooled correct firings n=%d; share >= 0.4/0.5/0.55/0.6/0.7: %s" % (len(OK), " / ".join(f"{100*(OK>=t).mean():.0f}%" for t in (0.4, .5, .55, .6, .7))))
print("| label | current category -> proposed | wrong firings | kept @current thr | kept @proposed |")
print("|---|---|---|---|---|")
for lab, v in sorted(W.items(), key=lambda kv: -len(kv[1])):
    v = np.array(v); c = CAT[lab]; ct = C.thr(lab, c); pc = P.cat[lab]
    pt = P.thr(lab, pc) if pc != IGN else None
    print(f"| {lab} | {c} -> {'DROP' if pc == IGN else pc} | {len(v)} | {(v>=ct).sum()} @{ct:.2f} | {'0 (dropped)' if pt is None else f'{(v>=pt).sum()} @{pt:.2f}'} |")

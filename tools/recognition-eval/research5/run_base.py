import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from sim import *
cur = Cfg("current")
for nm, rs in (("public", PUB), ("ipad photos", IPAD)):
    print(nm, summary(single(cur, rs)))
res, nsp, nsd = track_sim(cur)
print("frames tracks", summary([(t, p) for t, p, r in res]), "spurious tracks", nsp, "spurious sightings", nsd)
for t, p, r in res:
    if t != p: print("   ", t, "<-", p, "|", r["true_object"], "| recorded:", r["detector_label"])
rr = recorded_remap(cur)
print("recorded det-origin", len(rr), collections.Counter(t == p for t, rc, p, r in rr if t != "unclear"))

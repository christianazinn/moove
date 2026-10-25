import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
from run_cmp import report
new = cfg_full()
fp = collections.Counter()
for r in PUB:
    k = new.filt(raw[r["path"]]["det"])
    if k and k[0][0] == "box" and tgt(truth(r)) != "box": fp[(k[0][3], r["label"])] += 1
print("box FPs by label/truth:", fp.most_common())
report(new)
report(cfg_map("no dollhouse remap", remap={k: v for k, v in REMAP.items() if k != "dollhouse"}, lminc=LMINC))
V = {"room divider", "crib", "workbench", "humidifier", "space heater", "air purifier"}
for m in (0.0, 0.1):
    report(cfg_map(f"+veto margin {m}", drop=DROP - V, veto=V, lminc=LMINC)); 
    c = cfg_map("x", drop=DROP - V, veto=V, lminc=LMINC); c.veto_margin = m
    report(Cfg.__new__(Cfg) if False else c)

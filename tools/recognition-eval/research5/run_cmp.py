import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
def report(cfg):
    a = summary(single(cfg, PUB)); b = summary(single(cfg, IPAD))
    res, nsp, nsd = track_sim(cfg); c = summary([(t, p) for t, p, r in res])
    rr = [(t, p) for t, rc, p, r in recorded_remap(cfg) if t != "unclear"]
    d = sum(t == p for t, p in rr); dq = sum(p == "?" for t, p in rr)
    print(f"{cfg.name:38s} PUB acc {a['acc']:.1f} TP {a['TP']} FP {a['FP']} P {a['prec']:.1f} R {a['rec']:.1f} negFP {a['neg_fp']}/{a['n_neg']} | "
          f"IPADph acc {b['acc']:.1f} TP {b['TP']} FP {b['FP']} negFP {b['neg_fp']}/{b['n_neg']} | FRAMES acc {c['acc']:.1f} TP {c['TP']} FP {c['FP']} negFP {c['neg_fp']}/{c['n_neg']} spur {nsp} | REC right {d}/{len(rr)} (? {dq})")
if __name__ == "__main__":
    report(Cfg("current"))
    report(cfg_map("remap only", drop=set()))
    report(cfg_map("drop only", remap={}))
    report(cfg_map())
    for l in sorted(DROP | set(REMAP)):
        if l in REMAP: report(cfg_map(f"mapping minus remap {l}", remap={k: v for k, v in REMAP.items() if k != l}))
        else: report(cfg_map(f"mapping minus drop {l}", drop=DROP - {l}))

"""Before/after: overall + per-category precision/recall (public crops, iPad photos), keyframe tracking sim, recorded remap."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
from run_cmp import report
cfgs = [Cfg("current"), cfg_map("mapping/drops only"), cfg_full("mapping + thresholds")]
for c in cfgs: report(c)
cur, new = cfgs[0], cfgs[2]
for nm, rs in (("public crops", PUB), ("iPad photos", IPAD)):
    a = single(cur, rs); b = single(new, rs)
    tpa, fpa, pos = prf(a); tpb, fpb, _ = prf(b)
    cats = sorted(set(fpa) | set(fpb) | set(tpa) | {k for k in pos if k != "none"}, key=lambda k: -(fpa[k] + tpa[k] + pos[k]))
    print(f"\n### {nm}\n| category | n truth | TP before/after | FP before/after | P% before/after | R% before/after |\n|---|---|---|---|---|---|")
    for k in cats:
        if fpa[k] + tpa[k] + fpb[k] + tpb[k] == 0: continue
        pr = lambda tp, fp: f"{100*tp/(tp+fp):.0f}" if tp + fp else "-"
        rc = lambda tp: f"{100*tp/pos[k]:.0f}" if pos[k] else "-"
        print(f"| {k} | {pos[k]} | {tpa[k]}/{tpb[k]} | {fpa[k]}/{fpb[k]} | {pr(tpa[k], fpa[k])}/{pr(tpb[k], fpb[k])} | {rc(tpa[k])}/{rc(tpb[k])} |")
print("\n### recorded detector-origin objects: changed outcomes")
A = recorded_remap(cur); B = recorded_remap(new)
for (t, rc, p0, r), (_, _, p1, _) in zip(A, B):
    if p0 != p1: print(f"| {r['true_object']} | truth {t} | recorded {rc} | -> {p1} | {'FIX' if p1 == t else ('BREAK' if p0 == t else 'still wrong')} |")
print("\n### keyframe tracking sim: changed outcomes")
ra, _, _ = track_sim(cur); rb, _, _ = track_sim(new)
for (t, p0, r), (_, p1, _) in zip(ra, rb):
    if p0 != p1: print(f"| {r['true_object']} | truth {t} | {p0} -> {p1} | {'FIX' if p1 == t else ('BREAK' if p0 == t else 'still wrong')} |")

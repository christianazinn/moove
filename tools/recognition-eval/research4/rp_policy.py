"""Should the PE-Core-S/16-384 + V4 probe (lam=1, none bias +1, merges) re-check RoomPlan objects?

Origin: ScanSession writes geometry.json as RoomGeometry(room).objects + extras (ScanSession.swift:95-96),
so RoomPlan objects are the leading run of RoomPlan-category objects; scan 03-57-34 has RoomPlan's room.json.
Sets:  RP  = RoomPlan-origin photos (true origin);  CAT = photos whose recorded label is a RoomPlan category
(what you'd get if origin were inferred from the label: includes detector chair/table/TV/storage/fridge).
Policies (label-level probs p, recorded label r):
  a keep r;  b none if p[none]>=t else r;  c top if top in FAM[r] and p[top]-p[r]>=m else r;
  c+b  c then b;  d top if top!=r and p[top]-p[r]>=m (top may be none) else r.
Thresholds leave-one-scan-out on the same set (objective = correct decisions on scored rows, none = class;
ties -> most conservative threshold). Run: /tmp/claude-501/venv-eval/bin/python -I rp_policy.py
"""
import sys, json
sys.path.insert(0, "/tmp/claude-501/eval/research4")
import numpy as np
import r4_common as C
from r4_common import UL, UI, RPSET, view

C.origin = C.origin2
R = C.rows()
# multi-view probs (research3: strict views, pad 1.0, top-3 by score + auto photo, mean-prob)
z = np.load(f"{C.EVAL}/research3/mv_emb.npz")
recs = json.loads(str(z["recs"])); mrows = json.loads(str(z["rows"]))
MVP = {}
for i, mr in enumerate(mrows):
    vs = sorted([(r["score"], j) for j, r in enumerate(recs) if r["row"] == i and r["pad"] == 1.0 and r["score"] > 0], reverse=True)[:3]
    E = np.stack([z["auto"][i]] + [z["crops"][j] for _, j in vs])
    MVP[mr["path"]] = C.probs(E).mean(0)

FAM = {  # classifier labels a RoomPlan category may be relabelled to under policy c
    "storage": {"storage", "table"}, "table": {"table", "storage", "ottoman"},
    "chair": {"chair", "sofa", "ottoman", "bean bag"}, "sofa": {"sofa", "chair", "bed", "bean bag", "ottoman"},
    "bed": {"bed", "sofa"}, "television": {"television"},
    "refrigerator": {"refrigerator", "washerDryer", "microwave", "storage"}, "washerDryer": {"washerDryer", "refrigerator"},
    "oven": {"microwave"}, "stove": set(), "dishwasher": set(), "fireplace": set(), "stairs": set(),
    "sink": {"sink", "toilet", "bathtub"}, "toilet": {"sink", "toilet", "bathtub"}, "bathtub": {"sink", "toilet", "bathtub"},
}
INF = 9.0
T_GRID = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99, INF]
M_GRID = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, INF]


def decide(pol, rec, p, th):
    top = UL[int(p.argmax())]; pr = p[UI[rec]] if rec in UI else 0.0
    if pol == "a": return rec
    if pol == "b": return "none" if p[UI["none"]] >= th else rec
    if pol in ("c", "c+b"):
        m, t = (th, INF) if pol == "c" else th
        out = top if (top != rec and top in FAM.get(rec, set()) and p[UI[top]] - pr >= m) else rec
        return "none" if p[UI["none"]] >= t else out
    if pol == "d": return top if (top != rec and p[UI[top]] - pr >= th) else rec


GRIDS = {"a": [None], "b": T_GRID, "c": M_GRID, "c+b": [(m, t) for m in M_GRID for t in T_GRID], "d": M_GRID}


def conserv(th):  # bigger = more conservative
    return sum(th) if isinstance(th, tuple) else (th or 0)


def run(rows, pol, key="p", fixed=None):
    scans = sorted({r["scan"] for r in rows}); pred = {}; chosen = []
    for sc in scans:
        if fixed is not None:
            th = fixed
        else:
            oth = [r for r in rows if r["scan"] != sc and r["t"] != "unclear"]
            th = max(GRIDS[pol], key=lambda th: (sum(decide(pol, r["rec"], r[key], th) == r["t"] for r in oth), conserv(th)))
        chosen.append(th)
        for r in rows:
            if r["scan"] == sc: pred[r["path"]] = decide(pol, r["rec"], r[key], th)
    return pred, chosen


def score(rows, pred):
    real = [r for r in rows if r["t"] not in ("none", "unclear")]; non = [r for r in rows if r["t"] == "none"]
    sc = [r for r in rows if r["t"] != "unclear"]
    acc = np.mean([pred[r["path"]] == r["t"] for r in real]) if real else np.nan
    pn = [r for r in sc if pred[r["path"]] == "none"]; tp = sum(r["t"] == "none" for r in pn)
    P = tp / len(pn) if pn else np.nan; Rr = tp / len(non) if non else np.nan
    fix = sum(pred[r["path"]] == r["t"] != r["rec"] for r in sc); brk = sum(pred[r["path"]] != r["t"] == r["rec"] for r in sc)
    wrong2wrong = sum(pred[r["path"]] != r["rec"] and r["t"] not in (r["rec"], pred[r["path"]]) for r in sc)
    return acc, len(real), P, Rr, len(non), fix, brk, wrong2wrong, len(pn)


pct = lambda x: "n/a" if x != x else f"{100 * x:.1f}"
fmt_th = lambda th: "-" if th is None else ("never" if th == INF else (f"m={'inf' if th[0] == INF else th[0]},t={'never' if th[1] == INF else th[1]}" if isinstance(th, tuple) else str(th)))
out = []; w = out.append
SETS = {"RP (true RoomPlan origin)": [r for r in R if r["origin"] == "roomplan"],
        "CAT (recorded label is a RoomPlan category, any origin)": [r for r in R if (r["rec"] or "").lower() in RPSET],
        "DET-RPcat (detector objects with RoomPlan-category labels)": [r for r in R if r["origin"] == "detector" and (r["rec"] or "").lower() in RPSET]}
w("# Classifier re-check of RoomPlan objects (research4)\n")
w("Classifier: PE-Core-S/16-384 auto photo, V4 probe lam=1 + none bias +1, merges backpack->bag, monitor->television, "
  "shelf->storage; fixtures (radiator/shower curtain/towel rack) = none. Thresholds tuned leave-one-scan-out.\n")
for sname, rows in SETS.items():
    n_real = sum(r["t"] not in ("none", "unclear") for r in rows)
    w(f"\n## {sname}: {len(rows)} photos, {len(set(r['scan'] for r in rows))} scans, real {n_real}, "
      f"none {sum(r['t'] == 'none' for r in rows)}, unclear {sum(r['t'] == 'unclear' for r in rows)}\n")
    w("| policy | thresholds chosen per held-out scan | top-1 real % | none P % | none R % | #pred none | fixes | breaks | wrong->other wrong |\n|---|---|---|---|---|---|---|---|---|")
    for pol in ("a", "b", "c", "c+b", "d"):
        pred, ch = run(rows, pol)
        acc, nr, P, Rr, nn, fx, br, ww, npn = score(rows, pred)
        chs = sorted({fmt_th(c) for c in ch})
        w(f"| {pol} | {', '.join(chs)} | {pct(acc)} ({round(acc * nr) if acc == acc else 0}/{nr}) | {pct(P)} | {pct(Rr)} | {npn} | {fx} | {br} | {ww} |")
    w("\nFixed thresholds (not tuned; shows the curve):\n")
    w("| policy | threshold | top-1 real % | none P % | none R % | fixes | breaks |\n|---|---|---|---|---|---|---|")
    for pol, ths in (("b", [0.3, 0.5, 0.7, 0.9]), ("c", [0.3, 0.5, 0.7, 0.9]), ("d", [0.0, 0.3, 0.5, 0.7, 0.9])):
        for th in ths:
            pred, _ = run(rows, pol, fixed=th); acc, nr, P, Rr, nn, fx, br, ww, npn = score(rows, pred)
            w(f"| {pol} | {th} | {pct(acc)} | {pct(P)} | {pct(Rr)} | {fx} | {br} |")
    mv = [r for r in rows if r["path"] in MVP]
    if mv:
        for r in mv: r["pmv"] = MVP[r["path"]]
        w(f"\nMulti-view (auto + top-3 strict keyframes, mean prob; {len(mv)} photos in 6 scans with frames), LOSO:\n")
        w("| policy | key | top-1 real % | none P % | none R % | fixes | breaks |\n|---|---|---|---|---|---|---|")
        for pol in ("a", "b", "c", "d"):
            for key in ("p", "pmv"):
                pred, ch = run(mv, pol, key=key); acc, nr, P, Rr, nn, fx, br, ww, npn = score(mv, pred)
                w(f"| {pol} | {'auto' if key == 'p' else 'multi-view'} | {pct(acc)} (n={nr}) | {pct(P)} | {pct(Rr)} | {fx} | {br} |")

# per-object table for RP and DET-RPcat
for sname in ("RP (true RoomPlan origin)", "DET-RPcat (detector objects with RoomPlan-category labels)"):
    w(f"\n## Per object: {sname}\n")
    w("| scan | id | recorded | truth (object) | clf top-2 | p(none) | p(recorded) | b t=0.9 | c m=0.5 | d m=0.5 |\n|---|---|---|---|---|---|---|---|---|---|")
    for r in sorted(SETS[sname], key=lambda r: (r["scan"], r["rec"] or "")):
        p = r["p"]; i = p.argsort()[::-1]
        pr = p[UI[r["rec"]]] if r["rec"] in UI else float("nan")
        dec = [decide(pol, r["rec"], p, th) for pol, th in (("b", 0.9), ("c", 0.5), ("d", 0.5))]
        mark = lambda d: d if d == r["rec"] else (f"**{d}** (fix)" if d == r["t"] else (f"**{d}** (BREAK)" if r["t"] == r["rec"] else f"**{d}**"))
        w(f"| {r['scan'][5:16]} | {r['object_id'][:8]} | {r['rec']} | {r['t']} ({r['true_object']}) | {UL[i[0]]} {p[i[0]]:.2f}, {UL[i[1]]} {p[i[1]]:.2f} | {p[UI['none']]:.2f} | {pr:.2f} | {' | '.join(mark(d) for d in dec)} |")

# categories the classifier can't express
w("\n## RoomPlan categories vs classifier vocabulary\n")
for c in sorted(RPSET):
    cc = {"washerdryer": "washerDryer"}.get(c, c)
    w(f"- {cc}: {'expressible' if cc in UI else 'NOT expressible'}; family for policy c = {sorted(FAM.get(cc, set())) or '(none: keep)'}")
open("/tmp/claude-501/eval/research4/rp_policy_results.md", "w").write("\n".join(out) + "\n")
print("\n".join(out))

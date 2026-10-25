"""Single auto photo vs multi-keyframe aggregation, PE-Core-S/16-384 + V4 probe (lam=1).
Writes mv_results.md. Scoring as research2/common.py: fixture prediction (radiator/shower curtain/towel rack)
= none; ceiling fan = fan; merges backpack->bag, monitor->television, shelf->storage (pred and truth)."""
import json, os, sys, collections
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
R2 = "/tmp/claude-501/eval/research2"
z = np.load(f"{HERE}/mv_emb.npz")
recs = json.loads(str(z["recs"])); rows = json.loads(str(z["rows"]))
AUTO = z["auto"]; CR = z["crops"]
ac = json.load(open(f"{R2}/adapter_classes.json"))
W = np.load(f"{R2}/W_probe_public_lam1.npy").astype(np.float32)
LAB = np.array(ac["labels"], dtype=object)
MERGE = {"backpack": "bag", "monitor": "television", "shelf": "storage", "ceiling fan": "fan"}
FIX = {"radiator", "shower curtain", "towel rack"}
view = lambda l: "none" if l in FIX else MERGE.get(l, l)
VL = np.array([view(l) for l in LAB], dtype=object)
UL = sorted(set(VL)); UI = {l: i for i, l in enumerate(UL)}
A = np.zeros((len(LAB), len(UL)), np.float32)
for i, l in enumerate(VL): A[i, UI[l]] = 1


def probs(e):  # label-level probabilities (softmax over the 62 prompt classes, summed per final label)
    lg = 100 * np.atleast_2d(e) @ W.T
    p = np.exp(lg - lg.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
    return p @ A


# sanity: recomputed auto-photo embeddings vs the research2 cache
Z = np.load("/tmp/claude-501/eval/zs_pecore-s16.npz", allow_pickle=True)
zp = {p: i for i, p in enumerate(Z["paths"])}
ze = Z["emb"].astype(np.float32); ze /= np.linalg.norm(ze, axis=1, keepdims=True)
cos = [float(AUTO[i] @ ze[zp[r["path"]]]) for i, r in enumerate(rows) if r["path"] in zp]
truth = np.array([view(r["label"]) if r["label"] not in ("none", "unclear") else r["label"] for r in rows], dtype=object)
real = np.array([t not in ("none", "unclear") for t in truth]); isnone = truth == "none"; scored = truth != "unclear"

recs = [dict(r, i=j) for j, r in enumerate(recs)]


def relaxed(r):
    size = min(r["area"] / 0.2, 1); s = min(max(r["sharp"], .25), 1.25)
    return size * r["vis"] ** 3 * (1 - r["occ"]) ** 2 * s


def views(row, pad, pool):
    vs = [r for r in recs if r["row"] == row and r["pad"] == pad and (pool == "relaxed" or r["score"] > 0)]
    return sorted(vs, key=lambda r: (r["score"] > 0, r["score"] if r["score"] > 0 else relaxed(r)), reverse=True)


def agg(embs, how):
    P = probs(embs)
    if how == "mean-emb":
        m = embs.mean(0); return probs(m / np.linalg.norm(m))[0]
    if how == "mean-prob": return P.mean(0)
    if how == "max-conf": return P[P.max(1).argmax()]
    if how == "vote":
        v = np.zeros(len(UL));
        for p in P: v[p.argmax()] += 1
        return v + 1e-3 * P.sum(0)  # ties broken by summed probability
    raise ValueError(how)


def evaluate(pred):
    pred = np.array(pred, dtype=object)
    top1 = float(np.mean(pred[real] == truth[real]))
    pn = (pred == "none") & scored
    tp = (pn & isnone).sum()
    return top1, (tp / pn.sum() if pn.sum() else float("nan")), tp / isnone.sum(), pred


def run(pad, pool, k, how, with_auto, need_view=False):
    out, used = [], []
    for i in range(len(rows)):
        vs = views(i, pad, pool)
        vs = vs if k == "all" else vs[:k]
        embs = [CR[r["i"]] for r in vs]
        if with_auto or not embs: embs = [AUTO[i]] + embs  # fall back to the auto photo when no frame shows it
        used.append(len(vs))
        out.append(UL[int(agg(np.stack(embs), how).argmax())])
    return evaluate(out), used


lines = []
w = lines.append
pct = lambda x: "n/a" if x != x else f"{100 * x:.1f}"
base = evaluate([UL[int(probs(AUTO[i])[0].argmax())] for i in range(len(rows))])
nv = {pool: collections.Counter(len(views(i, 1.0, pool)) for i in range(len(rows))) for pool in ("strict", "relaxed")}
w(f"# Multi-keyframe vs single auto photo (PE-Core-S/16-384 + V4 probe lam=1, merges)\n")
w(f"Objects: {len(rows)} (real {real.sum()}, none {isnone.sum()}, unclear {(truth == 'unclear').sum()}) from 6 scans with saved frames.")
w(f"Auto-photo embedding check vs research2 cache: min cos {min(cos):.4f} over {len(cos)} photos.")
w(f"Views per object (strict CropPicker gates): {dict(sorted(nv['strict'].items()))}; relaxed: {dict(sorted(nv['relaxed'].items()))}\n")
w("| method | pool | pad | k | +auto | top-1 real % | none P % | none R % | changed vs auto (fixed/broken) |\n|---|---|---|---|---|---|---|---|---|")
w(f"| single auto photo | - | - | - | - | {pct(base[0])} | {pct(base[1])} | {pct(base[2])} | - |")
results = {}
for pool in ("strict", "relaxed"):
    for pad in (1.0, 1.3, 1.6):
        for with_auto in (False, True):
            for how in ("mean-emb", "vote", "max-conf", "mean-prob"):
                for k in (1, 3, 5, "all"):
                    if k == 1 and how != "mean-emb": continue
                    (t, p, r, pred), used = run(pad, pool, k, how, with_auto)
                    fx = int(((pred == truth) & (base[3] != truth) & scored).sum()); br = int(((pred != truth) & (base[3] == truth) & scored).sum())
                    results[(pool, pad, k, how, with_auto)] = pred
                    w(f"| {how if k != 1 else 'best frame'} | {pool} | {pad} | {k} | {'y' if with_auto else ''} | {pct(t)} | {pct(p)} | {pct(r)} | {fx}/{br} |")

# subset: objects with >=1 strict view (so the frame methods really ran)
has = np.array([len(views(i, 1.0, "strict")) > 0 for i in range(len(rows))])
w(f"\n## Subset with >=1 strict view (n real = {(has & real).sum()}, none = {(has & isnone).sum()})\n")
w("| method | top-1 real % | none P % | none R % |\n|---|---|---|---|")
def sub(pred):
    t = float(np.mean(pred[has & real] == truth[has & real])); pn = (pred == "none") & scored & has
    tp = (pn & isnone).sum(); return t, (tp / pn.sum() if pn.sum() else float("nan")), tp / (isnone & has).sum()
for nm, key in (("auto photo", None), ("best frame, pad 1.3", ("strict", 1.3, 1, "mean-emb", False)),
                ("mean-emb all, pad 1.3", ("strict", 1.3, "all", "mean-emb", False)),
                ("mean-emb all + auto, pad 1.3", ("strict", 1.3, "all", "mean-emb", True)),
                ("vote all + auto, pad 1.3", ("strict", 1.3, "all", "vote", True)),
                ("mean-emb 3 + auto, pad 1.3", ("strict", 1.3, 3, "mean-emb", True))):
    t, p, r = sub(base[3] if key is None else results[key])
    w(f"| {nm} | {pct(t)} | {pct(p)} | {pct(r)} |")

# per-object hard cases
w("\n## Per-object (hard cases + every object a multi-view method changed)\n")
w("| scan | obj | truth (true_object) | detector | auto | best frame 1.3 | mean-emb all+auto 1.3 | vote all+auto 1.3 | #views strict/relaxed | per-view labels (strict, 1.3) |\n|---|---|---|---|---|---|---|---|---|---|")
HARD = ("scooter", "vacuum", "box", "radiator", "curtain", "shower")
kA = ("strict", 1.3, "all", "mean-emb", True); kV = ("strict", 1.3, "all", "vote", True); kB = ("strict", 1.3, 1, "mean-emb", False)
for i, r in enumerate(rows):
    hard = any(h in " ".join(str(r[x]) for x in ("true_object", "detector_label", "label")).lower() for h in HARD)
    changed = len({base[3][i], results[kA][i], results[kV][i], results[kB][i]}) > 1
    if not (hard or changed): continue
    pv = [UL[int(probs(CR[v["i"]])[0].argmax())] for v in views(i, 1.3, "strict")]
    w(f"| {r['scan'][-8:]} | {r['object_id'][:8]} | {r['label']} ({r['true_object']}) | {r['detector_label']} | {base[3][i]} | {results[kB][i]} | "
      f"{results[kA][i]} | {results[kV][i]} | {nv['strict'] and len(views(i, 1.0, 'strict'))}/{len(views(i, 1.0, 'relaxed'))} | {', '.join(pv)} |")
open(f"{HERE}/mv_results.md", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))

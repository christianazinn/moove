"""Shipped classifier (V4 prompts + text-anchored linear probe, research2) + the ObjectRecheck
fusion, measured on the bench. Mirrors ios/MooveKit/Sources/MooveKit/Room/ObjectRecheck.swift.

Usage: python -I -B fuse.py <ObjectVocabulary.swift> [--export <dir>]
"""
import json, os, re, sys, collections
import numpy as np, torch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

R2 = f"{EV}/research2"
VOCAB = sys.argv[1]
EXPORT = sys.argv[sys.argv.index("--export") + 1] if "--export" in sys.argv else None

ad = json.load(open(f"{R2}/adapter_classes.json"))
names = ad["classes"]
labels = np.array([{"ceiling fan": "fan"}.get(l, l) for l in ad["labels"]], dtype=object)  # Moove category per class
W_text = np.load(f"{R2}/W_text_V4.npy").astype(np.float32)
W_ship = np.load(f"{R2}/W_probe_public_lam1.npy").astype(np.float32)
BIAS = np.load(f"{R2}/bias_none_plus1.npy").astype(np.float32)
fine = np.array([r.get("fine_label", r["label"]) for r in rows], dtype=object)

# ---- probe, public 5-fold CV grouped by source photo (same folds as analyze.py) ----
def fit_probe(W0, X, y, lam, steps=150, lr=0.01):  # research2/fewshot.py
    torch.manual_seed(0)
    W = torch.tensor(W0, requires_grad=True); W0t = torch.tensor(W0)
    Xt, yt = torch.tensor(X), torch.tensor(y)
    opt = torch.optim.Adam([W], lr=lr)
    for _ in range(steps):
        Wn = W / W.norm(dim=1, keepdim=True)
        loss = torch.nn.functional.cross_entropy(100 * Xt @ Wn.T, yt) + lam * ((W - W0t) ** 2).sum()
        opt.zero_grad(); loss.backward(); opt.step()
    with torch.no_grad():
        return (W / W.norm(dim=1, keepdim=True)).numpy()


def photo_id(path):
    b = os.path.basename(path)[:-4]
    return b if b.startswith("wm_") else b.rsplit("_", 1)[0]


group = np.array([photo_id(p) for p in paths], dtype=object)
pub_idx = np.where(is_pub)[0]
rng0 = np.random.default_rng(0)
ug = np.unique(group[pub_idx]); rng0.shuffle(ug)
fog = {g: i % 5 for i, g in enumerate(ug)}
fold = np.array([fog.get(g, -1) if p else -1 for g, p in zip(group, is_pub)])
ni = {n: i for i, n in enumerate(names)}
y = np.array([ni[f] if p else -1 for f, p in zip(fine, is_pub)])
Et = load_torch().astype(np.float32)
fold_W = {}
cache = f"{HERE}/out/probe_folds.npz"
if os.path.exists(cache):
    z = np.load(cache); fold_W = {k: z[f"w{k}"] for k in range(5)}
else:
    for fo in range(5):
        tr = pub_idx[fold[pub_idx] != fo]
        fold_W[fo] = fit_probe(W_text, Et[tr], y[tr], 1.0)
    np.savez(cache, **{f"w{k}": v for k, v in fold_W.items()})


def logits(E, W_all):
    """Public rows: held-out fold probe; iPad rows: the shipped probe (trained on all public)."""
    E = E / np.linalg.norm(E, axis=1, keepdims=True)
    L = 100 * E @ W_all.T
    for fo in range(5):
        te = pub_idx[fold[pub_idx] == fo]
        L[te] = 100 * E[te] @ fold_W[fo].T
    return L


EMBS = {"PyTorch": Et, "CoreML pal8 (Vision)": load_vision("vis_pal8")[0], "CoreML fp16 (Vision)": load_vision("vis_fp16")[0]}

# ---- merges (M3) and scoring ----
MERGE = {"backpack": "bag", "monitor": "television", "shelf": "storage", "ceiling fan": "fan"}
def mg(x):
    return MERGE.get(x, x)
FIX = {"radiator", "shower curtain", "towel rack"}
def view_m(p):
    return "none" if p in FIX else mg(p)
def acc_m(pred, mask):
    return float(np.mean([view_m(p) == mg(g) for p, g in zip(pred[mask], gt[mask])]))
def pub_acc_m(pred):
    return float(np.mean([mg(p) == mg(g) for p, g in zip(pred[is_pub], gt[is_pub])]))

# ---- detector vocabulary (Swift) ----
src = open(VOCAB).read()
blk = src.split("categories: [String: String] = [")[1].split("\n    ]")[0]
CAT = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', blk))
blk = src.split("minimumConfidence: [String: Float] = [")[1].split("\n    ]")[0]
MINC = {k: float(v) for k, v in re.findall(r'"([^"]+)":\s*([0-9.]+)', blk)}
DEFC = float(re.search(r"defaultMinimumConfidence: Float = ([0-9.]+)", src).group(1))
RP = {c.lower() for c in re.findall(r'"([^"]+)"', src.split("roomPlanCategories: Set<String> = [")[1].split("]")[0])}

# ---- ObjectRecheck (keep in sync with the Swift) ----
# Footprint priors (m): (short, long, height) ranges; a category may have several shapes.
PRIORS = {
    "scooter": [((0.40, 0.65), (0.95, 1.25), (1.00, 1.30)), ((0.10, 0.45), (0.55, 1.00), (0.60, 1.05))],
    "vacuum": [((0.25, 0.40), (0.28, 0.45), (1.00, 1.20)), ((0.18, 0.30), (0.20, 0.32), (1.00, 1.32)), ((0.28, 0.36), (0.28, 0.36), (0.07, 0.11))],
    "mop": [((0.03, 0.20), (0.15, 0.45), (1.10, 1.50))],
    "bicycle": [((0.40, 0.80), (1.50, 1.90), (0.90, 1.20))],
    "stroller": [((0.45, 0.70), (0.75, 1.05), (0.95, 1.10))],
    "box": [((0.30, 0.34), (0.40, 0.43), (0.30, 0.34)), ((0.44, 0.47), (0.45, 0.48), (0.39, 0.42)), ((0.44, 0.47), (0.45, 0.62), (0.58, 0.63))],
    "radiator": [((0.05, 0.25), (0.40, 2.00), (0.30, 0.90))],
    "shower curtain": [((0.02, 0.30), (1.50, 2.00), (1.60, 2.00))],
}
SLACK = 0.15


def size_fit(cat, dims, factor):
    """True/False when `cat` has a prior: does the box fit any of its shapes, with bounds
    widened to [lo / factor, hi * factor]? None without a prior."""
    if cat not in PRIORS or dims is None:
        return None
    w, h, d = dims
    v = (min(w, d), max(w, d), h)
    return any(all(lo / factor <= x <= hi * factor for x, (lo, hi) in zip(v, shape)) for shape in PRIORS[cat])


GROUPS = sorted({mg(l) for l in labels})
NOT_OBJECT = {"none"} | FIX


def probs(L, bias=True):
    L = L + (BIAS if bias else 0)
    p = np.exp(L - L.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
    G = np.zeros((len(L), len(GROUPS)))
    gi = {g: i for i, g in enumerate(GROUPS)}
    for j, l in enumerate(labels):
        G[:, gi[mg(l)]] += p[:, j]
    return G, p


def recheck(det, G, p, dims, rej, margin, oov, veto):
    """-> (action, category). action in keep / relabel / reject / unknown."""
    gi = {g: i for i, g in enumerate(GROUPS)}
    order = np.argsort(-G)
    top = GROUPS[order[0]]; pt = G[order[0]]
    factor = {"none": None, "strict": 1 + SLACK, "loose": 2.0, "loose+sure": 2.0}[veto]
    sure = 0.9 if veto == "loose+sure" else 9.0  # a classifier this sure beats a partial LiDAR box
    def clearly_off(cat, prob=0.0):
        if factor is None or prob >= sure:
            return False
        f = size_fit(cat, dims, factor)
        return f is False
    if top in NOT_OBJECT and pt >= rej and not clearly_off(top, pt):
        return "reject", top
    d = mg(det)
    pd = G[gi[d]] if d in gi else None
    # best object group (skip not-object groups)
    objs = [g for g in (GROUPS[i] for i in order) if g not in NOT_OBJECT]
    best = objs[0]; pb = G[gi[best]]
    # table vs storage: LiDAR height decides a near tie (0.9 m cut)
    if dims is not None and {best, objs[1]} == {"table", "storage"} and abs(pb - G[gi[objs[1]]]) < margin:
        best = "storage" if dims[1] > 0.9 else "table"; pb = G[gi[best]]
    if best != d:
        ok = (pb - pd >= margin) if pd is not None else (pb >= oov)
        if ok and not clearly_off(best, pb):
            # the member category with the higher probability (e.g. monitor vs television)
            mem = sorted({l for l in labels if mg(l) == best})
            cat = max(mem, key=lambda c: sum(p[j] for j, l in enumerate(labels) if l == c))
            return "relabel", cat
    if clearly_off(det) and (pd is None or pd < 0.5):
        return "unknown", "other"
    return "keep", det


# ---- iPad: recorded label + object dims ----
dims_of = {}
for r in rows:
    if r["split"] != "ipad":
        continue
    gpath = f"{BENCH}/ipad_raw/{r['scan']}/geometry.json"
    if os.path.exists(gpath):
        g = json.load(open(gpath))
        for o in g["objects"]:
            if o["id"] == r["object_id"]:
                dims_of[r["path"]] = o["dimensions"]
rec = np.array([(r.get("detector_label") or "none") if r["split"] == "ipad" else None for r in rows], dtype=object)
# Origin (as research4's origin2): RoomPlan if in the scan's room.json, else if inside the leading run of
# RoomPlan categories in geometry.json (ScanSession writes RoomGeometry(room).objects + extras).
def origin(r):
    oid = r["object_id"].upper()
    rj = f"{BENCH}/ipad_raw/{r['scan']}/room.json"
    if os.path.exists(rj):
        return "roomplan" if oid in {o["identifier"].upper() for o in json.load(open(rj)).get("objects", [])} else "detector"
    objs = json.load(open(f"{BENCH}/ipad_raw/{r['scan']}/geometry.json"))["objects"]
    k = 0
    while k < len(objs) and objs[k]["category"].lower() in RP:
        k += 1
    idx = {o["id"].upper(): i for i, o in enumerate(objs)}
    return "roomplan" if idx.get(oid, 10**9) < k else "detector"
ORIGIN = np.array([origin(r) if r["split"] == "ipad" else None for r in rows], dtype=object)
is_det = np.array([o == "detector" for o in ORIGIN])
is_rp = np.array([o == "roomplan" for o in ORIGIN])
RP_SKIP = {"dishwasher", "oven", "stove", "fireplace", "stairs", "sink", "toilet", "bathtub"}
RP_REJECT = 0.7

# ---- public: simulated detector category (app thresholds, as analyze.py) ----
raw = {}
for l in open(f"{EV}/vision_raw.jsonl"):
    o = json.loads(l)
    raw[o["path"]] = o["det"]
def det_pred(dets):
    best, bs = "none", -1
    for lab, s, box in dets:
        c = CAT.get(lab)
        if c is None:
            continue
        if s >= MINC.get(c, DEFC) and s > bs:
            best, bs = c, s
    return best
pub_det = np.array([det_pred(raw[p]) if is_pub[i] else None for i, p in enumerate(paths)], dtype=object)


def run(E_name, rej, margin, oov, veto, bias=True, rp_policy=True):
    L = logits(EMBS[E_name], W_ship)
    G, P = probs(L, bias)
    out = np.empty(N, dtype=object); act = np.empty(N, dtype=object)
    for i in range(N):
        if is_ipad[i]:
            if not is_det[i]:
                # RoomPlan objects: reject only (p(none) + p(fixtures) >= 0.7), never relabel.
                pn = sum(G[i, GROUPS.index(g)] for g in NOT_OBJECT)
                if rp_policy and rec[i] not in RP_SKIP and pn >= RP_REJECT:
                    out[i], act[i] = "none", "rp-reject"
                else:
                    out[i], act[i] = rec[i], "roomplan"
                continue
            det = rec[i]
        else:
            det = pub_det[i]
            if det == "none":
                out[i], act[i] = None, "nodet"
                continue
        a, c = recheck(det, G[i], P[i], dims_of.get(paths[i]), rej, margin, oov, veto)
        act[i] = a
        out[i] = "none" if a == "reject" else c
    return out, act


def public_score(out):
    """Public rows the detector fired on: final label right (fixture truth: rejected)."""
    m = is_pub & (pub_det != "none")
    ok = [(o == "none") if g in FIX else (mg(o) == mg(g)) for o, g in zip(out[m], gt[m])]
    return float(np.mean(ok)), int(m.sum())


def ipad_report(out):
    real = ipad_obj
    a_raw = acc(out, real, ipad_view); a_m = acc_m(out, real)
    p, r = none_pr(out)
    return a_raw, a_m, p, r


if __name__ == "__main__":
    lines = []
    w = lines.append
    # 1. classifier alone
    w("### Classifier alone (argmax class, M3 merges in scoring unless noted)\n")
    w("| Embedding | weights | Public top-1 % | Public top-1 % (no merge) | iPad top-1 % | iPad top-1 % (no merge) | none P % | none R % |")
    w("|---|---|---|---|---|---|---|---|")
    for en in EMBS:
        for wn, bias in (("probe", False), ("probe + none bias +1", True)):
            L = logits(EMBS[en], W_ship) + (BIAS if bias else 0)
            pr = labels[L.argmax(1)].astype(object)
            p, r = none_pr(pr)
            w(f"| {en} | {wn} | {pct(pub_acc_m(pr))} | {pct(acc(pr, is_pub))} | {pct(acc_m(pr, ipad_obj))} | {pct(acc(pr, ipad_obj, ipad_view))} | {pct(p)} | {pct(r)} |")
        Lz = 100 * (EMBS[en] / np.linalg.norm(EMBS[en], axis=1, keepdims=True)) @ W_text.T
        pr = labels[Lz.argmax(1)].astype(object)
        p, r = none_pr(pr)
        w(f"| {en} | V4 text only | {pct(pub_acc_m(pr))} | {pct(acc(pr, is_pub))} | {pct(acc_m(pr, ipad_obj))} | {pct(acc(pr, ipad_obj, ipad_view))} | {pct(p)} | {pct(r)} |")
    # 2. tune on public (CoreML embeddings, as shipped)
    EN = "CoreML pal8 (Vision)"
    grid = []
    for rej in (0.3, 0.4, 0.5, 0.6, 0.7):
        for margin in (0.0, 0.1, 0.2, 0.3, 0.4, 0.5):
            for oov in (0.5, 0.6, 0.7, 0.8, 0.9):
                s, n = public_score(run(EN, rej, margin, oov, "loose")[0])
                grid.append((s, rej, margin, oov))
    grid.sort(key=lambda t: (-t[0], -t[1], -t[2], -t[3]))
    best = grid[0]
    w(f"\nTuned on public (detector fired, n={public_score(run(EN, 0.5, 0.2, 0.7, 'loose')[0])[1]}): best score {pct(best[0])} at reject {best[1]}, margin {best[2]}, oov {best[3]}; top 5: {[(round(a,3),b,c,d) for a,b,c,d in grid[:5]]}")
    _, REJ, MAR, OOV = best
    json.dump({"reject": REJ, "margin": MAR, "oov": OOV}, open(f"{HERE}/out/tuned.json", "w"))
    # 3. fused pipeline on iPad
    w("\n### Fused pipeline, iPad split (RoomPlan-origin objects: reject-only at 0.7)\n")
    w("| Pipeline | iPad top-1 % (n=83) | merged (M3) % | none P % | none R % (n=30) | public (detector fired) % |")
    w("|---|---|---|---|---|---|")
    a, am, p, r = ipad_report(rec)
    w(f"| Recorded scan output | {pct(a)} | {pct(am)} | {pct(p)} | {pct(r)} | n/a |")
    res = {}
    for veto in ("none", "strict", "loose", "loose+sure"):
        for bias in (True, False):
            out, act = run(EN, REJ, MAR, OOV, veto, bias)
            res[(veto, bias)] = (out, act)
            a, am, p, r = ipad_report(out)
            w(f"| + classifier recheck (size veto: {veto}, none bias {'+1' if bias else 'off'}) | {pct(a)} | {pct(am)} | {pct(p)} | {pct(r)} | {pct(public_score(out)[0])} |")
    out, act = run(EN, REJ, MAR, OOV, "loose+sure", True, rp_policy=False)
    a, am, p, r = ipad_report(out)
    w(f"| shipped, but RoomPlan objects not rechecked at all | {pct(a)} | {pct(am)} | {pct(p)} | {pct(r)} | {pct(public_score(out)[0])} |")
    out, act = run("PyTorch", REJ, MAR, OOV, "loose+sure", True)
    a, am, p, r = ipad_report(out)
    w(f"| same, PyTorch embeddings (loose+sure veto, bias +1) | {pct(a)} | {pct(am)} | {pct(p)} | {pct(r)} | {pct(public_score(out)[0])} |")
    out, act = res[("loose+sure", True)]
    m = is_det
    w(f"\nDetector objects on iPad: {m.sum()}; actions: {dict(collections.Counter(act[m]))}; RoomPlan objects: {is_rp.sum()}, actions {dict(collections.Counter(act[is_rp]))}")
    # 4. hard cases
    w("\n### Hard cases (iPad)\n")
    w("| Photo | Truth | Recorded | Fused | Action | Box W×H×D (m) |")
    w("|---|---|---|---|---|---|")
    for i in np.where(is_ipad)[0]:
        r_ = rows[i]
        t = r_["true_object"]; rc = rec[i]
        hard = ("scooter" in t) or rc == "vacuum" or (rc == "bin") or (rc == "heater") or ("shower curtain" in t) or ("radiator" in t)
        if not hard:
            continue
        d = dims_of.get(paths[i])
        ds = "×".join(f"{x:.2f}" for x in d) if d else "?"
        w(f"| {os.path.basename(paths[i])[:-4]} | {gt[i]} ({t}) | {rc} | {out[i]} | {act[i]} | {ds} |")
    # 5. changes
    w("\n### Every change the recheck made on iPad\n")
    w("| Photo | Truth | Recorded | Fused | Right before → after |")
    w("|---|---|---|---|---|")
    for i in np.where(is_ipad)[0]:
        if out[i] != rec[i]:
            ok0 = view_m(rec[i]) == mg(gt[i]); ok1 = view_m(out[i]) == mg(gt[i])
            w(f"| {os.path.basename(paths[i])[:-4]} | {gt[i]} ({rows[i]['true_object']}) | {rec[i]} | {out[i]} | {'yes' if ok0 else 'no'} → {'yes' if ok1 else 'no'} |")
    print("\n".join(lines))
    open(f"{HERE}/out/fuse_results.md", "w").write("\n".join(lines))
    if EXPORT:
        os.makedirs(EXPORT, exist_ok=True)
        W_ship.astype("<f2").tofile(f"{EXPORT}/ObjectClassifierLabels.f16")
        meta = {
            "model": "PE-Core-S/16-384 (Meta FAIR, Apache-2.0), image tower in ObjectClassifier.mlpackage",
            "about": "logits = logitScale * normalize(embedding) . W[class] + bias[class]; W is ObjectClassifierLabels.f16 "
                     "(float16 little-endian, classes x dimension, row-major): PE-Core text embeddings of the prompts, "
                     "fine-tuned as a text-anchored linear probe on public crops. category 'none' = not a movable object.",
            "dimension": int(W_ship.shape[1]),
            "logitScale": 100.0,
            "templates": ["a photo of a {}.", "a photo of a {} in a room.", "a cropped photo of a {}."],
            "classes": [{"id": n, "category": str(l), "bias": float(b), "prompts": ad["prompts"][n]} for n, l, b in zip(names, labels, BIAS)],
        }
        json.dump(meta, open(f"{EXPORT}/ObjectClassifierLabels.json", "w"), indent=1)
        # Swift parity fixture: a few iPad detector objects (Core ML embedding, detector
        # category, box) with what this script decides for them.
        E = EMBS[EN] / np.linalg.norm(EMBS[EN], axis=1, keepdims=True)
        L = logits(EMBS[EN], W_ship); G, P = probs(L)
        want = ["72066CED", "AC5DB808", "644162E4", "1162E1D1", "02F7BF6A", "2DCF0F49", "B4817201", "C36C8113", "7B501609", "E7AB5A46", "4426C67D", "45269E6D"]
        cases = []
        for i in np.where(is_det)[0]:
            if not any(k in paths[i] for k in want):
                continue
            a, c = recheck(rec[i], G[i], P[i], dims_of[paths[i]], REJ, MAR, OOV, "loose+sure")
            gi = {g: k for k, g in enumerate(GROUPS)}
            cases.append({"photo": os.path.basename(paths[i])[:-4], "truth": rows[i]["true_object"], "detector": rec[i],
                          "dimensions": [round(x, 4) for x in dims_of[paths[i]]], "embedding": [round(float(x), 5) for x in E[i]],
                          "action": a, "category": c, "top": GROUPS[int(G[i].argmax())], "topProbability": round(float(G[i].max()), 4)})
        json.dump(cases, open(f"{EXPORT}/recheck-cases.json", "w"))
        print("cases", len(cases))
        print("exported", W_ship.shape)

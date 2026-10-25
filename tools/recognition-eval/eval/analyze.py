"""Scores every method on the bench and writes results.md.

Inputs: /tmp/claude-501/bench/manifest.jsonl, vision_raw.jsonl (from vision_eval),
optional zs_<key>.npz (from zs_eval.py). Run: /tmp/claude-501/venv-eval/bin/python -I analyze.py
"""
import json, re, os, glob, collections
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = "/tmp/claude-501/bench"
VOCAB = "/Users/rioschillmoeller/moove/ios/MooveKit/Sources/MooveKit/Room/ObjectVocabulary.swift"
rng = np.random.default_rng(0)

rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
raw = {r["path"]: r for r in (json.loads(l) for l in open(f"{HERE}/vision_raw.jsonl"))}
N = len(rows)
gt = np.array([r["label"] for r in rows], dtype=object)
fine = np.array([r.get("fine_label", r["label"]) for r in rows], dtype=object)
is_pub = np.array([r["split"] == "public" for r in rows])
is_ipad = ~is_pub
ipad_obj = is_ipad & ~np.isin(gt, ["none", "unclear"])
ipad_none = is_ipad & (gt == "none")
ipad_scored = is_ipad & (gt != "unclear")

# ---------- app vocabulary (parsed from Swift) ----------
src = open(VOCAB).read()
blk = src.split("categories: [String: String] = [")[1].split("\n    ]")[0]
CAT = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', blk))
blk = src.split("minimumConfidence: [String: Float] = [")[1].split("\n    ]")[0]
MINC = {k: float(v) for k, v in re.findall(r'"([^"]+)":\s*([0-9.]+)', blk)}
DEFC = float(re.search(r"defaultMinimumConfidence: Float = ([0-9.]+)", src).group(1))

# Scoring equivalences: a ceiling fan is labeled "fan" on the iPad and the detector
# only has "electric fan" -> fan, so fan == ceiling fan. Fixed fixtures (radiator,
# shower curtain, towel rack) are labeled "none" on the iPad (not movable objects), so a
# prediction of one of those counts as "none" there.
CANON = {"ceiling fan": "fan"}
FIXTURE = {"radiator", "shower curtain", "towel rack"}


def canon(x):
    return CANON.get(x, x)


def ipad_view(p):
    return "none" if p in FIXTURE else canon(p)


# ---------- method predictions ----------
P, MS, NOTES = {}, {}, {}


def det_pred(dets, thr=None):
    best, bs = "none", -1
    for lab, s, box in dets:
        c = CAT.get(lab)
        if c is None:
            continue
        t = MINC.get(c, DEFC) if thr is None else thr
        if s >= t and s > bs:
            best, bs = c, s
    return best, bs


dets = [raw[r["path"]]["det"] for r in rows]
P["Detector (app thresholds)"] = np.array([det_pred(d)[0] for d in dets], dtype=object)
P["Detector (any score >= 0.15)"] = np.array([det_pred(d, 0.15)[0] for d in dets], dtype=object)
def det_pred_area(dets):
    # crops are centred on the object: prefer big passing boxes (score * sqrt(area))
    best, bs = "none", -1
    for lab, sc, box in dets:
        c = CAT.get(lab)
        if c is None or sc < MINC.get(c, DEFC):
            continue
        v = sc * max(box[2] * box[3], 1e-4) ** 0.5
        if v > bs:
            best, bs = c, v
    return best


P["Detector (app thr., largest-box pick)"] = np.array([det_pred_area(d) for d in dets], dtype=object)
det_score = np.array([det_pred(d)[1] for d in dets])
MS["Detector (app thresholds)"] = MS["Detector (any score >= 0.15)"] = MS["Detector (app thr., largest-box pick)"] = np.array([raw[r["path"]]["ms_det"] for r in rows])
rec = np.array([(r.get("detector_label") or "none") if r["split"] == "ipad" else None for r in rows], dtype=object)

# VNClassifyImageRequest -> Moove category (hand mapping; unmapped labels are skipped)
VNMAP = {
    "backpack": "backpack", "bag": "bag", "purse": "bag", "paper_bag": "bag", "sack": "bag",
    "bath": "bathtub", "jacuzzi": "bathtub", "bed": "bed", "crib": "crib",
    "bicycle": "bicycle", "tricycle": "bicycle", "cardboard_box": "box", "carton": "box", "crate": "box",
    "cart": "cart", "shopping_cart": "cart", "wagon": "cart", "electric_fan": "fan",
    "armchair": "chair", "chair": "chair", "chair_other": "chair", "folding_chair": "chair",
    "high_chair": "chair", "swivel_chair": "chair", "stool": "stool", "guitar": "guitar", "ukulele": "guitar",
    "iron_clothing": "ironing board", "lamp": "lamp", "laptop": "laptop", "microwave": "microwave",
    "toaster_oven": "microwave", "computer_monitor": "monitor", "plant": "plant", "decorative_plant": "plant",
    "bonsai": "plant", "refrigerator": "refrigerator", "scooter": "scooter", "shower": "shower curtain",
    "washbasin": "sink", "kitchen_sink": "sink", "bathroom_faucet": "sink", "kitchen_faucet": "sink",
    "sofa": "sofa", "chaise": "sofa", "cabinet": "storage", "bookshelf": "storage", "closet": "storage",
    "stroller": "stroller", "suitcase": "suitcase", "luggage": "suitcase", "briefcase": "bag",
    "table": "table", "desk": "table", "television": "television", "toilet_seat": "toilet",
    "trash_can": "trash can", "vacuum": "vacuum", "laundry_machine": "washerDryer", "yoga": "yoga mat",
    "painting": "art", "frame": "art", "easel": "art", "piano": "piano", "printer": "printer",
    "speakers_music": "speaker", "treadmill": "treadmill", "dumbbell": "weights", "barbell": "weights",
    "computer_tower": "computer", "computer_keyboard": "keyboard", "toolbox": "toolbox", "wheelchair": "wheelchair",
    "motorcycle": "motorcycle", "skateboard": "skateboard", "surfboard": "surfboard", "drum": "drums",
    "violin": "violin", "cello": "cello", "clock": "clock", "vase": "vase", "christmas_tree": "decor",
    "toy": "toy", "stuffed_animals": "toy", "basket_container": "basket", "bucket": "basket",
    "stove": "stove", "kitchen_oven": "oven", "dishwasher": "dishwasher", "fireplace": "fireplace",
    "bench": "bench", "seat": "chair", "pillow": "pillow", "mower": "lawn mower", "grill": "grill",
}


def vnc_pred(res, t):
    for lab, c in res:
        if c < t:
            break
        if lab in VNMAP:
            return VNMAP[lab]
    return "none"


vres = [raw[r["path"]]["vnc"] for r in rows]
# threshold tuned on the public split (max accuracy)
best_t = max(np.arange(0.02, 0.5, 0.02), key=lambda t: np.mean([canon(vnc_pred(v, t)) == canon(g) for v, g, p in zip(vres, gt, is_pub) if p]))
P[f"VNClassify (t={best_t:.2f})"] = np.array([vnc_pred(v, best_t) for v in vres], dtype=object)
MS[f"VNClassify (t={best_t:.2f})"] = np.array([raw[r["path"]]["ms_vnc"] for r in rows])
VNC_KEY = f"VNClassify (t={best_t:.2f})"

# ---------- kNN on embeddings ----------
def photo_id(path):
    # lvis_<img>_<crop>.jpg / oi_<img>_<crop>.jpg -> source photo; wm_<file>.jpg is one photo each
    b = os.path.basename(path)[:-4]
    return b if b.startswith("wm_") else b.rsplit("_", 1)[0]


group = np.array([photo_id(r["path"]) for r in rows], dtype=object)
pub_idx = np.where(is_pub)[0]
ug = np.unique(group[pub_idx])
rng.shuffle(ug)
fold_of_group = {g: i % 5 for i, g in enumerate(ug)}
fold = np.array([fold_of_group.get(g, -1) if p else -1 for g, p in zip(group, is_pub)])


def knn_all(X, name, ms):
    """k=1 / k=5 kNN (cosine). Public: 5-fold CV grouped by source photo. iPad: full public gallery.
    Also returns nearest cosine distance for the reject rule."""
    X = X / np.linalg.norm(X, axis=1, keepdims=True)
    D = 1 - X @ X[pub_idx].T  # [N, n_pub] cosine distance
    pred1 = np.empty(N, dtype=object)
    pred5 = np.empty(N, dtype=object)
    near = np.zeros(N)
    labs = gt[pub_idx]
    for i in range(N):
        d = D[i].copy()
        if is_pub[i]:
            d[fold[pub_idx] == fold[i]] = np.inf  # exclude own fold
        o = np.argsort(d)[:5]
        pred1[i] = labs[o[0]]
        near[i] = d[o[0]]
        votes = collections.defaultdict(float)
        for j in o:
            votes[labs[j]] += 1.0 / (d[j] + 1e-3)  # distance-weighted vote
        pred5[i] = max(votes, key=votes.get)
    # reject threshold: 95th percentile of nearest distance of correctly classified public CV items
    ok = is_pub & (pred5 == gt)
    thr = float(np.percentile(near[ok], 95))
    rej = np.where(near > thr, "none", pred5).astype(object)
    P[f"{name} kNN k=1"] = pred1
    P[f"{name} kNN k=5"] = pred5
    P[f"{name} kNN k=5 + reject"] = rej
    for k in ("k=1", "k=5", "k=5 + reject"):
        MS[f"{name} kNN {k}"] = ms
    NOTES[f"{name} kNN k=5 + reject"] = f"reject if nearest cosine distance > {thr:.3f} (95th pct of correct public CV)"
    # iPad rows only: gallery = public + iPad photos from OTHER scans (leave-one-scan-out),
    # including their `none` photos as a "none" class. Public rows keep the CV prediction.
    scan = np.array([r.get("scan", "") for r in rows], dtype=object)
    gal_ip = np.where(is_ipad & (gt != "unclear"))[0]
    Dg = 1 - X @ X[gal_ip].T
    loso = rej.copy()
    for i in np.where(is_ipad)[0]:
        d = np.concatenate([D[i], np.where(scan[gal_ip] == scan[i], np.inf, Dg[i])])
        lb = np.concatenate([labs, gt[gal_ip]])
        o = np.argsort(d)[:5]
        votes = collections.defaultdict(float)
        for j in o:
            votes[lb[j]] += 1.0 / (d[j] + 1e-3)
        loso[i] = "none" if d[o[0]] > thr else max(votes, key=votes.get)
    P[f"{name} kNN k=5 + reject, +iPad gallery (LOSO)"] = loso
    MS[f"{name} kNN k=5 + reject, +iPad gallery (LOSO)"] = ms
    NOTES[f"{name} kNN k=5 + reject, +iPad gallery (LOSO)"] = "iPad only: gallery adds iPad photos (incl. `none`) from the other scans, leave-one-scan-out; public columns = same as k=5 + reject"
    return near, thr


FP = np.array([raw[r["path"]]["fp"] for r in rows], dtype=np.float32)
fp_near, fp_thr = knn_all(FP, "FeaturePrint", np.array([raw[r["path"]]["ms_fp"] for r in rows]) + 0.0)
# Note: feature-print vectors are unit norm (rev 2), so cosine == VNFeaturePrintObservation.computeDistance ranking.

# ---------- zero-shot ----------
ZS = {}
for f in sorted(glob.glob(f"{HERE}/zs_*.npz")):
    z = np.load(f, allow_pickle=True)
    key = os.path.basename(f)[3:-4]
    assert list(z["paths"]) == [r["path"] for r in rows]
    lg, labs = z["logits"], z["labels"]
    pz = labs[lg.argmax(1)].astype(object)
    nm = {"siglip-so400m": "SigLIP so400m/14 (v1)", "clip-l14": "CLIP ViT-L/14", "pecore-s16": "PE-Core-S/16-384",
          "siglip2-b16": "SigLIP2 B/16"}.get(key, key)
    P[f"{nm} zero-shot"] = pz
    MS[f"{nm} zero-shot"] = z["ms"]
    NOTES[f"{nm} zero-shot"] = f"device {z['device']}; ms = image encoder incl. preprocessing"
    ZS[nm] = (lg, labs, z["emb"])
    knn_all(z["emb"], nm, z["ms"])

# ---------- fusion ----------
D_ = P["Detector (app thresholds)"]
K5 = P["FeaturePrint kNN k=5"]
KR = P["FeaturePrint kNN k=5 + reject"]
V = P[VNC_KEY]
# F1: detector, but only when the feature-print kNN agrees (top-5 vote) -> else none
P["F1 Detector AND FP-kNN agree"] = np.where(D_ == K5, D_, "none").astype(object)
# F2: detector; if detector says none, fall back to accepted FP-kNN
P["F2 Detector, else FP-kNN(reject)"] = np.where(D_ == "none", KR, D_).astype(object)
# F3: VNClassify as none-filter: drop the detector label when VNClassify maps to nothing
P["F3 Detector unless VNClassify=none"] = np.where(V == "none", "none", D_).astype(object)
for k in ("F1 Detector AND FP-kNN agree", "F2 Detector, else FP-kNN(reject)"):
    MS[k] = MS["Detector (app thresholds)"] + MS["FeaturePrint kNN k=1"]
MS["F3 Detector unless VNClassify=none"] = MS["Detector (app thresholds)"] + MS[VNC_KEY]
for zn, (lg, labs, _) in ZS.items():
    if zn.startswith("CLIP"):
        continue
    zk = f"{zn} zero-shot"
    Z = P[zk]
    # ZS + confidence reject: label probability (softmax summed over a label's prompt classes);
    # threshold = 5th percentile of p on correct public predictions.
    pr_ = np.exp(lg - lg.max(1, keepdims=True)); pr_ /= pr_.sum(1, keepdims=True)
    pmax = np.array([pr_[i][labs == Z[i]].sum() for i in range(N)])
    okz = is_pub & (np.array([canon(a) for a in Z]) == np.array([canon(b) for b in gt]))
    tz = float(np.percentile(pmax[okz], 5))
    P[f"{zk} + reject"] = np.where(pmax < tz, "none", Z).astype(object)
    MS[f"{zk} + reject"] = MS[zk]
    NOTES[f"{zk} + reject"] = f"none if label probability < {tz:.2f} (5th pct of correct public)"
    # F4: detector and ZS must agree (ZS alone when the detector finds nothing)
    k4 = f"F4 {zn}: ZS, none if detector disagrees"
    P[k4] = np.where(D_ == Z, Z, np.where(D_ == "none", Z, "none")).astype(object)
    MS[k4] = MS["Detector (app thresholds)"] + MS[zk]
    # F5: ZS and kNN on the same embedding (public gallery) must agree
    k5 = f"F5 {zn}: ZS AND same-embedding kNN agree"
    P[k5] = np.where(Z == P[f"{zn} kNN k=5"], Z, "none").astype(object)
    MS[k5] = MS[zk]
    # F6: ZS, but none when the in-domain (LOSO iPad + public) kNN says none
    k6 = f"F6 {zn}: ZS, none if LOSO-kNN (iPad negatives) says none"
    P[k6] = np.where(P[f"{zn} kNN k=5 + reject, +iPad gallery (LOSO)"] == "none", "none", Z).astype(object)
    MS[k6] = MS[zk]
    NOTES[k6] = "iPad only uses the other scans' photos; on public it equals ZS + (kNN distance reject)"

# ---------- metrics ----------
def acc(pred, mask, view=canon):
    return float(np.mean([view(p) == canon(g) for p, g in zip(pred[mask], gt[mask])])) if mask.any() else float("nan")


def macro(pred, mask):
    cls = sorted(set(gt[mask]))
    return float(np.mean([acc(pred, mask & (gt == c)) for c in cls]))


def none_pr(pred):
    m = ipad_scored
    pn = np.array([ipad_view(p) == "none" for p in pred]) & m
    tp = (pn & ipad_none).sum()
    prec = tp / pn.sum() if pn.sum() else float("nan")
    return prec, tp / ipad_none.sum(), int(pn.sum())


def pct(x):
    return "n/a" if x != x else f"{100 * x:.1f}"


out = []
w = out.append
w("# Moove object classification benchmark\n")
w(f"Bench: {is_pub.sum()} public crops ({len(set(fine[is_pub]))} fine classes, {len(set(gt[is_pub]))} Moove labels) + "
  f"{is_ipad.sum()} iPad scan photos ({ipad_obj.sum()} real objects, {ipad_none.sum()} `none`, {(gt == 'unclear').sum()} `unclear`). "
  "Machine: Apple M5, macOS, offline.\n")
w("Scoring notes: `ceiling fan` == `fan`. On the iPad split a prediction of a fixed fixture (radiator / shower curtain / towel rack) counts as `none`, "
  "matching how those were labeled. iPad top-1 excludes `none`/`unclear` rows; none-rejection uses all non-`unclear` iPad rows "
  "(positive = truth `none`). kNN public numbers are 5-fold CV grouped by source photo (no crop of the same photo in train and test).\n")

methods = list(P)
w("## Summary\n")
w(f"| Method | Public top-1 % | Public macro % | iPad top-1 % (n={ipad_obj.sum()}) | iPad none-reject precision % | recall % (n={ipad_none.sum()}) | median ms/img |")
w("|---|---|---|---|---|---|---|")
summary_rows = []
recorded = rec
pr = none_pr(recorded)
w(f"| Recorded on-device detector (scan output) | n/a | n/a | {pct(acc(recorded, ipad_obj))} | {pct(pr[0])} | {pct(pr[1])} | n/a |")
for m in methods:
    pr = none_pr(P[m])
    ms = np.median(MS[m][is_pub | is_ipad]) if m in MS else float("nan")
    w(f"| {m} | {pct(acc(P[m], is_pub))} | {pct(macro(P[m], is_pub))} | {pct(acc(P[m], ipad_obj, ipad_view))} | {pct(pr[0])} | {pct(pr[1])} | {ms:.1f} |")
RP = set(re.findall(r'"([^"]+)"', src.split("roomPlanCategories: Set<String> = [")[1].split("]")[0]))
rpm = ipad_obj & np.array([g.lower() in RP for g in gt])
w(f"| Recorded, objects in RoomPlan categories only (n={rpm.sum()}) | | | {pct(acc(recorded, rpm))} | | | |")
w(f"| Recorded, detector-only categories (n={(ipad_obj & ~rpm).sum()}) | | | {pct(acc(recorded, ipad_obj & ~rpm))} | | | |")
w("")
w("The recorded scan label comes from RoomPlan for RoomPlan categories (bed, chair, table, storage, sink, toilet, bathtub, television...) and from the multi-frame detector otherwise, so it is not directly comparable to single-image classifiers on those classes.\n")
for m, n in NOTES.items():
    w(f"- {m}: {n}")
w("")

# per-class (public)
CLS = ["scooter", "vacuum", "bicycle", "chair", "sofa", "bed", "table", "storage", "shelf", "lamp", "television", "monitor",
       "laptop", "refrigerator", "toilet", "sink", "bathtub", "mirror", "plant", "rug", "suitcase", "backpack", "bag",
       "trash can", "box", "guitar", "heater", "radiator", "ironing board", "stroller", "shower curtain", "towel rack",
       "fan", "ceiling fan", "cart", "ladder", "ottoman", "microwave", "washerDryer", "yoga mat"]
short = {m: m for m in methods}
cols = ["Detector (app thresholds)", VNC_KEY, "FeaturePrint kNN k=1", "FeaturePrint kNN k=5"] + [m for m in methods if m.endswith("zero-shot")] + [m for m in methods if m.endswith("kNN k=5") and not m.startswith("FeaturePrint")]
w("## Per-class top-1 accuracy, public split (%)\n")
w("| Class (n) | " + " | ".join(cols) + " |")
w("|---" * (len(cols) + 1) + "|")
for c in CLS:
    msk = is_pub & (gt == c)
    if not msk.any():
        continue
    w(f"| {c} ({msk.sum()}) | " + " | ".join(f"{100 * acc(P[m], msk):.0f}" for m in cols) + " |")
w("")
w("Detector-vocabulary gaps: the detector has no prompt for " + ", ".join(sorted({c for c in set(gt[is_pub]) if c not in set(CAT.values())})) +
  " (RoomPlan covers bathtub/sink/toilet in the app), so it scores 0 on those by construction.\n")

# per-class iPad
w("## Per-class top-1 accuracy, iPad split (%; real objects only)\n")
icols = ["Recorded detector"] + cols
w("| Class (n) | " + " | ".join(icols) + " |")
w("|---" * (len(icols) + 1) + "|")
for c in sorted(set(gt[ipad_obj])):
    msk = ipad_obj & (gt == c)
    vals = [acc(recorded, msk)] + [acc(P[m], msk, ipad_view) for m in cols]
    w(f"| {c} ({msk.sum()}) | " + " | ".join(f"{100 * v:.0f}" for v in vals) + " |")
w("")

# confusions (main variants only; every method's predictions are in predictions.json)
KEY = [m for m in methods if not (m.endswith("k=1") or (m.endswith("+ reject") and "kNN" in m) or m.startswith("F1") or m.startswith("F3")
                                  or m.startswith("F4") or m.startswith("F5") or (m.startswith("CLIP") and "kNN" in m) or "any score" in m)]
w("## Top-10 confusion pairs (public split, truth -> predicted, count)\n")
for m in KEY:
    cc = collections.Counter((g, canon(p)) for g, p in zip(gt[is_pub], P[m][is_pub]) if canon(g) != canon(p))
    w(f"**{m}**: " + "; ".join(f"{a}->{b} {n}" for (a, b), n in cc.most_common(10)) + "\n")
w("## Top-10 confusion pairs (iPad split incl. `none`, truth -> predicted)\n")
cc = collections.Counter((g, canon(p)) for g, p in zip(gt[ipad_scored], recorded[ipad_scored]) if canon(g) != canon(p))
w("**Recorded detector**: " + "; ".join(f"{a}->{b} {n}" for (a, b), n in cc.most_common(10)) + "\n")
for m in KEY:
    cc = collections.Counter((g, ipad_view(p)) for g, p in zip(gt[ipad_scored], P[m][ipad_scored]) if canon(g) != ipad_view(p))
    w(f"**{m}**: " + "; ".join(f"{a}->{b} {n}" for (a, b), n in cc.most_common(10)) + "\n")

# hard cases
hcols = ["Detector (app thresholds)", VNC_KEY, "FeaturePrint kNN k=5 + reject", "FeaturePrint kNN k=5 + reject, +iPad gallery (LOSO)"] + [m for m in methods if m.endswith("zero-shot")] + [m for m in methods if m.startswith("F2 ") or m.startswith("F6 ")]
w("## iPad hard cases (every iPad photo the recorded scan got wrong)\n")
w("Cells show the prediction; **bold** = right (truth, or `none` for a non-object/fixture).\n")
w("| Photo | Truth (object) | Recorded | " + " | ".join(hcols) + " |")
w("|---" * (len(hcols) + 3) + "|")
idx = [i for i in np.where(is_ipad)[0] if not rows[i]["correct"]]
idx.sort(key=lambda i: (gt[i] in ("none", "unclear"), gt[i], rows[i]["true_object"]))
for i in idx:
    r = rows[i]

    def cell(p):
        ok = gt[i] != "unclear" and ipad_view(p) == canon(gt[i])
        return f"**{p}**" if ok else p
    w(f"| {os.path.basename(r['path'])[:28]} | {gt[i]} ({r['true_object']}) | {recorded[i]} | " + " | ".join(cell(P[m][i]) for m in hcols) + " |")
w("")
w(f"Correct among these {len(idx)} hard cases (excl. unclear): " + "; ".join(
    f"{m}: {sum(1 for i in idx if gt[i] != 'unclear' and ipad_view(P[m][i]) == canon(gt[i]))}" for m in hcols) + "\n")

# rejection threshold sweep for feature print (oracle on iPad, for reference)
w("## FeaturePrint kNN: reject-threshold sweep on iPad (reference only; the reported threshold is tuned on public)\n")
w("| nearest-distance threshold | iPad top-1 % | none precision % | none recall % |")
w("|---|---|---|---|")
for t in [0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.6, fp_thr]:
    pr_ = np.where(fp_near > t, "none", K5).astype(object)
    p_, r_, _ = none_pr(pr_)
    w(f"| {t:.3f}{' (tuned)' if t == fp_thr else ''} | {pct(acc(pr_, ipad_obj, ipad_view))} | {pct(p_)} | {pct(r_)} |")
w("")
open(f"{HERE}/results.md", "w").write("\n".join(out))
json.dump({m: list(map(str, P[m])) for m in P} | {"paths": [r["path"] for r in rows]}, open(f"{HERE}/predictions.json", "w"))
print("\n".join(out))

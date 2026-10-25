"""Evaluates detector label->category maps and thresholds (current vs proposed) on:
 A public crops, B iPad photos (single-image app pick), C full-keyframe tracking sim (6 scans),
 D recorded scan outcomes remapped (10 scans, detector-origin objects)."""
import sys, json, os, collections; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from common import *
IGN = "_ignore"
TRUTHS_DETECTABLE = set(CANON.get(c, c) for c in CAT.values())

def tgt(t):  # what the detector should say for this truth
    t = CANON.get(t, t)
    return t if t in TRUTHS_DETECTABLE else "none"

class Cfg:
    def __init__(self, name, cat=None, minc=None, lminc=None, defc=DEFC, veto=frozenset(), veto_margin=0.0):
        self.name = name; self.cat = dict(cat or CAT); self.minc = dict(MINC if minc is None else minc)
        self.lminc = dict(lminc or {}); self.defc = defc; self.veto = set(veto); self.veto_margin = veto_margin
    def thr(self, lab, c): return self.lminc.get(lab, self.minc.get(c, self.defc))
    def filt(self, dets):
        """DetectionFilter.filter: mapped, >= threshold, dedupe per category IoU>0.5. Veto labels (fixture proxies)
        suppress any object box they overlap (IoU>0.5) with score >= theirs - margin."""
        vetoes = [(s, b) for l, s, b in dets if l in self.veto and s >= self.defc]
        cand = []
        for l, s, b in dets:
            c = self.cat.get(l)
            if c is None or c == IGN or l in self.veto or s < self.thr(l, c): continue
            if any(vs >= s - self.veto_margin and iou(vb, b) > 0.5 for vs, vb in vetoes): continue
            cand.append((c, s, b, l))
        cand.sort(key=lambda x: -x[1]); kept = []
        for d in cand:
            if not any(k[0] == d[0] and iou(k[2], d[2]) > 0.5 for k in kept): kept.append(d)
        return kept
    def pick(self, dets):
        k = self.filt(dets)
        return k[0][0] if k else "none"

def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1]); x1, y1 = min(a[0]+a[2], b[0]+b[2]), min(a[1]+a[3], b[1]+b[3])
    i = max(x1-x0, 0)*max(y1-y0, 0); u = a[2]*a[3]+b[2]*b[3]-i
    return i/u if u > 0 else 0

PUB = [r for r in rows if r["split"] == "public"]
IPAD = [r for r in rows if r["split"] == "ipad" and r["label"] != "unclear"]

def single(cfg, rs):
    """returns list of (target, pred)"""
    return [(tgt(truth(r)), cfg.pick(raw[r["path"]]["det"])) for r in rs]

def prf(pairs):
    tp = collections.Counter(); fp = collections.Counter(); pos = collections.Counter()
    for t, p in pairs:
        pos[t] += 1
        if p != "none":
            if p == t: tp[p] += 1
            else: fp[p] += 1
    return tp, fp, pos

def summary(pairs):
    tp, fp, pos = prf(pairs)
    n_obj = sum(v for k, v in pos.items() if k != "none"); TP = sum(tp.values()); FP = sum(fp.values())
    neg = [p for t, p in pairs if t == "none"]
    return dict(acc=100*sum(t == p for t, p in pairs)/len(pairs), TP=TP, FP=FP, prec=100*TP/max(TP+FP, 1),
                rec=100*TP/max(n_obj, 1), neg_fp=sum(p != "none" for p in neg), n_neg=len(neg), n_obj=n_obj)

# ---------- C: full-frame tracking sim ----------
FA = [json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_assoc.jsonl")]
FD = collections.defaultdict(list)  # (scan, frame) -> list of (label, score, box, obj, truth)
for a in FA: FD[(a["scan"], a["frame"])].append(a)
OBJ_T = {}
for r in rows:
    if r["split"] == "ipad": OBJ_T[(r["scan"], r["object_id"])] = r
FRAME_SCANS = sorted(set(a["scan"] for a in FA))

def track_sim(cfg, single_conf=0.85):
    """Per scanned object (with truth) in the 6 framed scans: confirmed category = >=2 frames, or one frame >= 0.85;
    winner = max total confidence. Unmatched sightings counted per (scan, category) as spurious candidates."""
    per_obj = collections.defaultdict(lambda: collections.defaultdict(list)); spur = collections.defaultdict(list)
    for (scan, fr), ds in FD.items():
        seen = set()
        for d in sorted(ds, key=lambda d: -d["score"]):
            c = cfg.cat.get(d["label"])
            if c is None or c == IGN or d["label"] in cfg.veto or d["score"] < cfg.thr(d["label"], c): continue
            if "obj" in d:
                if any(v["obj"] == d["obj"] and v["label"] in cfg.veto and v["score"] >= d["score"] - cfg.veto_margin and v["score"] >= cfg.defc for v in ds if "obj" in v): continue
                key = (d["obj"], c)
                if key in seen: continue
                seen.add(key); per_obj[(scan, d["obj"])][c].append(d["score"])
            else: spur[(scan, c)].append(d["score"])
    res = []
    for (scan, oid), r in OBJ_T.items():
        if scan not in FRAME_SCANS or r["label"] == "unclear": continue
        cats = per_obj.get((scan, oid), {})
        conf = {c: sum(v) for c, v in cats.items() if len(v) >= 2 or max(v) >= single_conf}
        p = max(conf, key=conf.get) if conf else "none"
        res.append((tgt(truth(r)), p, r))
    nsp = sum(1 for k, v in spur.items() if len(v) >= 2 or max(v) >= single_conf)
    return res, nsp, sum(len(v) for v in spur.values())

# ---------- D: recorded outcomes remap ----------
RPSET = {c.lower() for c in ["bed", "sofa", "chair", "table", "storage", "refrigerator", "stove", "oven", "dishwasher", "washerDryer",
         "sink", "toilet", "bathtub", "fireplace", "television", "stairs"]}
GEO = {}
for sc in os.listdir(f"{BENCH}/ipad_raw"):
    gp = f"{BENCH}/ipad_raw/{sc}/geometry.json"
    if not os.path.exists(gp): continue
    objs = json.load(open(gp))["objects"]; k = 0
    while k < len(objs) and objs[k]["category"].lower() in RPSET: k += 1
    GEO[sc] = {o["id"].upper(): i < k for i, o in enumerate(objs)}
def det_origin(r):
    if r["detector_source"].startswith("roomplan"): return False
    return not GEO.get(r["scan"], {}).get(r["object_id"].upper(), True)
REC = [r for r in rows if r["split"] == "ipad" and det_origin(r)]
OBJ_LABELS = collections.defaultdict(collections.Counter)
for a in FA:
    if "obj" in a: OBJ_LABELS[(a["scan"], a["obj"])][a["label"]] += 1

def recorded_remap(cfg):
    """New category for each detector-origin recorded object: if every label of the recorded category maps to the
    same new category (or all ignored) -> that; else use the labels seen on that object in keyframes; else '?'."""
    out = []
    for r in REC:
        rc = r["detector_label"]
        labs = [l for l, c in CAT.items() if c == rc]
        new = {cfg.cat.get(l) if l not in cfg.veto else IGN for l in labs}
        if len(new) == 1: p = new.pop()
        else:
            seen = [l for l in OBJ_LABELS.get((r["scan"], r["object_id"]), {}) if l in labs]
            nn = {cfg.cat.get(l) if l not in cfg.veto else IGN for l in seen}
            p = nn.pop() if len(nn) == 1 else "?"
        p = "none" if p == IGN else p
        out.append((tgt(truth(r)) if r["label"] != "unclear" else "unclear", rc, p, r))
    return out

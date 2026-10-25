"""Shared loading for research4: RoomPlan-origin objects, classifier probabilities (V4 probe lam=1 + none bias +1)."""
import json, os, glob, collections
import numpy as np

BENCH = "/tmp/claude-501/bench"; EVAL = "/tmp/claude-501/eval"; R2 = f"{EVAL}/research2"
MAN = [json.loads(l) for l in open(f"{BENCH}/ipad_manifest.jsonl")]
Z = np.load(f"{EVAL}/zs_pecore-s16.npz", allow_pickle=True)
ZP = {p: i for i, p in enumerate(Z["paths"])}
EMB = Z["emb"].astype(np.float32); EMB /= np.linalg.norm(EMB, axis=1, keepdims=True)
AC = json.load(open(f"{R2}/adapter_classes.json"))
W = np.load(f"{R2}/W_probe_public_lam1.npy").astype(np.float32)
BIAS = np.load(f"{R2}/bias_none_plus1.npy").astype(np.float32)
LAB = np.array(AC["labels"], dtype=object)
MERGE = {"backpack": "bag", "monitor": "television", "shelf": "storage", "ceiling fan": "fan"}
FIX = {"radiator", "shower curtain", "towel rack"}
view = lambda l: "none" if l in FIX else MERGE.get(l, l)
VL = np.array([view(l) for l in LAB], dtype=object)
UL = sorted(set(VL)); UI = {l: i for i, l in enumerate(UL)}
A = np.zeros((len(LAB), len(UL)), np.float32)
for i, l in enumerate(VL): A[i, UI[l]] = 1


def probs(e, bias=True):
    """label-level probs: softmax over 62 prompt classes of 100*e@W.T (+1 none/fixture bias), summed per label."""
    lg = 100 * np.atleast_2d(e) @ W.T + (BIAS if bias else 0)
    p = np.exp(lg - lg.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
    return p @ A


# RoomPlan categories per scan
RP = {}
for d in glob.glob(f"{BENCH}/ipad_raw/*/room.json"):
    sc = os.path.basename(os.path.dirname(d)); r = json.load(open(d))
    RP[sc] = {o["identifier"].upper(): (list(o["category"].keys())[0], list(o.get("confidence", {}).keys() or ["?"])[0])
              for o in r.get("objects", [])}
RP_CATS = ["bathtub", "bed", "chair", "dishwasher", "fireplace", "oven", "refrigerator", "sink", "sofa", "stairs",
           "storage", "stove", "table", "television", "toilet", "washerDryer"]


def origin(m):
    oid = m["object_id"].upper(); rp = RP.get(m["scan"], {})
    if oid in rp: return "roomplan"
    pre = os.path.basename(m["path"]).rsplit("_", 1)[1][:-4].upper()
    hits = [k for k in rp if k.startswith(pre)]
    return "roomplan" if hits else "detector"


def truth(m):
    l = m["label"]
    return l if l in ("none", "unclear") else view(l)


def rows():
    out = []
    for m in MAN:
        e = EMB[ZP[m["path"]]]
        o = origin(m)
        rc = RP.get(m["scan"], {}).get(m["object_id"].upper(), (None, None))
        out.append(dict(m, origin=o, rp_cat=rc[0], rp_conf=rc[1], t=truth(m), rec=view(m["detector_label"]),
                        p=probs(e)[0], p_nobias=probs(e, bias=False)[0]))
    return out


# ---- origin from geometry.json ordering (ScanSession: geometry = RoomGeometry(room).objects + extras) ----
RPSET = {"bed", "sofa", "chair", "table", "storage", "refrigerator", "stove", "oven", "dishwasher", "washerdryer",
         "sink", "toilet", "bathtub", "fireplace", "television", "stairs"}
GEO = {}
for d in glob.glob(f"{BENCH}/ipad_raw/*/geometry.json"):
    sc = os.path.basename(os.path.dirname(d)); objs = json.load(open(d))["objects"]
    k = 0
    while k < len(objs) and objs[k]["category"].lower() in RPSET: k += 1
    GEO[sc] = {o["id"].upper(): dict(idx=i, cat=o["category"], dims=o["dimensions"], rp_prefix=i < k, n_prefix=k)
               for i, o in enumerate(objs)}


def origin2(m):
    """'roomplan' if in room.json, else if inside the leading run of RoomPlan categories in geometry.json."""
    oid = m["object_id"].upper()
    if m["scan"] in RP: return "roomplan" if oid in RP[m["scan"]] else "detector"
    g = GEO[m["scan"]].get(oid)
    if g is None: return "?"
    return "roomplan" if g["rp_prefix"] else "detector"

"""Shared bench scoring (same rules as the benchmark's analyze.py)."""
import json
import numpy as np

EV = "/tmp/claude-501/ev" "al"
BENCH = "/tmp/claude-501/bench"
HERE = "/private/tmp/claude-501/-Users-rioschillmoeller/8507c509-f62d-4008-95b2-3422d3e75c57/scratchpad/cls"
rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
paths = [r["path"] for r in rows]
N = len(rows)
gt = np.array([r["label"] for r in rows], dtype=object)
is_pub = np.array([r["split"] == "public" for r in rows])
is_ipad = ~is_pub
ipad_obj = is_ipad & ~np.isin(gt, ["none", "unclear"])
ipad_none = is_ipad & (gt == "none")
ipad_scored = is_ipad & (gt != "unclear")
CANON = {"ceiling fan": "fan"}
FIXTURE = {"radiator", "shower curtain", "towel rack"}


def canon(x):
    return CANON.get(x, x)


def ipad_view(p):
    return "none" if p in FIXTURE else canon(p)


def acc(pred, mask, view=canon):
    return float(np.mean([view(p) == canon(g) for p, g in zip(pred[mask], gt[mask])]))


def none_pr(pred):
    p = np.array([ipad_view(x) == "none" for x in pred])
    t = gt == "none"
    m = ipad_scored
    tp = (p & t & m).sum()
    return (tp / max((p & m).sum(), 1), tp / max((t & m).sum(), 1))


def load_labels(vocab):
    meta = json.load(open(f"{HERE}/out/labels_{vocab}.json"))
    T = np.fromfile(f"{HERE}/out/labels_{vocab}.f16", dtype="<f2").astype(np.float32).reshape(len(meta["classes"]), -1)
    return meta, T


def load_vision(name):
    E = np.fromfile(f"{HERE}/out/{name}.f32", dtype=np.float32).reshape(-1, 512)
    ps = open(f"{HERE}/out/{name}.paths").read().split("\n")
    assert ps == paths
    ms = np.array([float(x) for x in open(f"{HERE}/out/{name}.ms").read().split("\n")])
    return E, ms


def load_torch():
    z = np.load(f"{EV}/zs_pecore-s16.npz", allow_pickle=True)
    assert list(z["paths"]) == paths
    return z["emb"]


def category_probs(E, meta, T):
    """Softmax over prompt classes, summed per category -> (categories, P [N, K])."""
    lg = meta["logitScale"] * E @ T.T
    p = np.exp(lg - lg.max(1, keepdims=True))
    p /= p.sum(1, keepdims=True)
    cls_cat = [c["category"] for c in meta["classes"]]
    cats = sorted(set(cls_cat))
    idx = {c: i for i, c in enumerate(cats)}
    P = np.zeros((E.shape[0], len(cats)), dtype=np.float64)
    for j, c in enumerate(cls_cat):
        P[:, idx[c]] += p[:, j]
    return cats, P


def pct(x):
    return f"{100 * x:.1f}"

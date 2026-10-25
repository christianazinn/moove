"""Shared data loading, scoring and PE-Core text encoding for research2 experiments.

Scoring matches ../analyze.py: canon(ceiling fan)=fan; on iPad a fixture prediction
(radiator / shower curtain / towel rack) counts as none; iPad top-1 over real objects (n=83);
none P/R over non-unclear iPad rows (positives = truth none, n=30).
"""
import json, os, hashlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
EVAL = os.path.dirname(HERE)
BENCH = "/tmp/claude-501/bench"
rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
N = len(rows)
gt = np.array([r["label"] for r in rows], dtype=object)
is_pub = np.array([r["split"] == "public" for r in rows])
is_ipad = ~is_pub
ipad_obj = is_ipad & ~np.isin(gt, ["none", "unclear"])
ipad_none = is_ipad & (gt == "none")
ipad_scored = is_ipad & (gt != "unclear")
scan = np.array([r.get("scan", "") for r in rows], dtype=object)

Z = np.load(f"{EVAL}/zs_pecore-s16.npz", allow_pickle=True)
assert list(Z["paths"]) == [r["path"] for r in rows]
EMB = Z["emb"].astype(np.float32)
EMB /= np.linalg.norm(EMB, axis=1, keepdims=True)

CANON = {"ceiling fan": "fan"}
FIXTURE = {"radiator", "shower curtain", "towel rack"}


def canon(x):
    return CANON.get(x, x)


def ipad_view(p):
    return "none" if p in FIXTURE else canon(p)


def photo_id(path):
    b = os.path.basename(path)[:-4]
    return b if b.startswith("wm_") else b.rsplit("_", 1)[0]


group = np.array([photo_id(r["path"]) for r in rows], dtype=object)


def acc(pred, mask, view=canon, merge=None):
    m = merge or (lambda x: x)
    return float(np.mean([m(view(p)) == m(canon(g)) for p, g in zip(pred[mask], gt[mask])])) if mask.any() else float("nan")


def none_pr(pred):
    pn = np.array([ipad_view(p) == "none" for p in pred]) & ipad_scored
    tp = (pn & ipad_none).sum()
    return (tp / pn.sum() if pn.sum() else float("nan")), tp / ipad_none.sum()


def metrics(pred, merge=None):
    p, r = none_pr(pred)
    return dict(pub=acc(pred, is_pub, merge=merge), ipad=acc(pred, ipad_obj, ipad_view, merge=merge), nP=p, nR=r)


def fmt(m):
    f = lambda x: "n/a" if x != x else f"{100 * x:.1f}"
    return f"{f(m['pub'])} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])}"


HDR = "| Variant | Public top-1 % | iPad top-1 % (n=83) | none P % | none R % (n=30) |\n|---|---|---|---|---|"

# ---------------- text tower (cached) ----------------
_CACHE_F = f"{HERE}/text_cache.npz"
_cache = dict(np.load(_CACHE_F, allow_pickle=True)) if os.path.exists(_CACHE_F) else {}
_model = None
SCALE = None


def _load():
    global _model, _tok, SCALE
    if _model is None:
        os.environ["HF_HUB_OFFLINE"] = "1"
        import open_clip, torch
        name = f"local-dir:{EVAL}/dl/pecore"
        m, _, _ = open_clip.create_model_and_transforms(name)
        _model, _tok = m.eval(), open_clip.get_tokenizer(name)
        SCALE = float(m.logit_scale.exp().item())


def encode(texts):
    """Unit-norm text embeddings [len(texts), 512] (CPU, cached by string)."""
    key = lambda t: hashlib.md5(t.encode()).hexdigest()
    todo = [t for t in dict.fromkeys(texts) if key(t) not in _cache]
    if todo:
        _load()
        import torch
        with torch.no_grad():
            for i in range(0, len(todo), 64):
                e = _model.encode_text(_tok(todo[i:i + 64])).float()
                e = (e / e.norm(dim=-1, keepdim=True)).numpy()
                for t, v in zip(todo[i:i + 64], e):
                    _cache[key(t)] = v
        np.savez(_CACHE_F, **_cache)
    return np.stack([_cache[key(t)] for t in texts])


def class_weights(classes, templates):
    """classes: {name: (label, [synonyms])}; templates: list of format strings, or per-class override
    (a synonym containing '{}'-free full sentence starting with '!' is used verbatim)."""
    names = list(classes)
    W = []
    for n in names:
        texts = []
        for s in classes[n][1]:
            if s.startswith("!"):
                texts.append(s[1:])
            else:
                texts += [t.format(s) for t in templates]
        e = encode(texts).mean(0)
        W.append(e / np.linalg.norm(e))
    return names, np.array([classes[n][0] for n in names], dtype=object), np.stack(W).astype(np.float32)


def predict(W, labels, X=EMB, scale=100.0):
    lg = scale * X @ W.T
    return labels[lg.argmax(1)].astype(object), lg

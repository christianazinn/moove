"""Few-shot adaptation of PE-Core-S/16-384 on the saved image embeddings.

Methods (all produce one 512 x C weight matrix, except Tip-Adapter which also keeps a cache):
  ZS      zero-shot text weights (prompt set chosen by --prompts)
  PROTO   W_c = norm(a * t_c + (1-a) * mean_img_c)   (classes without images keep t_c)
  TIP     Tip-Adapter (training-free): 100*xW^T + beta * exp(-g (1 - x F^T)) Y      (cache F = train crops)
  PROBE   text-anchored linear probe: min CE(100 x W^T) + lam ||W - W_text||^2, W rows renormalised
Protocols:
  public:   5-fold CV grouped by source photo (same folds as ../analyze.py); k shots per fine class drawn
            from the 4 training folds.
  iPad:     train on k shots/class of ALL public crops, test on the 120 iPad photos.
  iPad+LOSO: as iPad but the training set also gets every iPad photo from the OTHER scans (incl. none).
Hyper-parameters are picked on public CV only (never on iPad).
Run: /tmp/claude-501/venv-eval/bin/python -I fewshot.py
"""
import sys, json, collections
sys.path.insert(0, "/tmp/claude-501/eval/research2")
from common import *
import torch
import prompts as PR

torch.set_num_threads(4)
fine = np.array([r.get("fine_label", r["label"]) for r in rows], dtype=object)

# same grouped folds as analyze.py
rng0 = np.random.default_rng(0)
pub_idx = np.where(is_pub)[0]
ug = np.unique(group[pub_idx]); rng0.shuffle(ug)
fog = {g: i % 5 for i, g in enumerate(ug)}
fold = np.array([fog.get(g, -1) if p else -1 for g, p in zip(group, is_pub)])


def text_set(which):
    if which == "V0":
        C = PR.build()
    else:  # V4: targeted public-tuned synonyms + brief negatives
        C = PR.build()
        TGT = dict(bag=["duffel bag"], table=["table", "wooden table", "dining table", "coffee table"],
                   shelf=["wall shelf", "floating shelf", "shelving unit"],
                   monitor=["computer monitor", "computer monitor on a desk"])
        for k, v in TGT.items():
            C[k] = (C[k][0], v)
        for k, v in PR.NEG_BRIEF.items():
            C[k] = ("none", v)
    names, labels, W = class_weights(C, PR.BASE_T)
    return names, labels, W, C


def row_class(names, labels, W0):
    """prompt-class index per row: public -> fine label; iPad -> best-scoring prompt class among those whose
    Moove label equals the truth (none: neg classes + fixtures). -1 for unclear."""
    ni = {n: i for i, n in enumerate(names)}
    y = np.full(N, -1)
    lg = EMB @ W0.T
    for i in range(N):
        if is_pub[i]:
            y[i] = ni[fine[i]]
        elif gt[i] != "unclear":
            ok = np.array([canon(l) == canon(gt[i]) or (gt[i] == "none" and l in FIXTURE) for l in labels])
            if ok.any():
                y[i] = int(np.argmax(np.where(ok, lg[i], -9)))
    return y


def sample(train_idx, y, k, rng):
    if k is None:
        return train_idx
    out = []
    for c in np.unique(y[train_idx]):
        ii = train_idx[y[train_idx] == c]
        out += list(rng.choice(ii, min(k, len(ii)), replace=False))
    return np.array(out)


def fit_proto(W0, X, y, a):
    W = W0.copy()
    for c in np.unique(y):
        m = X[y == c].mean(0); m /= np.linalg.norm(m)
        v = a * W0[c] + (1 - a) * m
        W[c] = v / np.linalg.norm(v)
    return W


def fit_probe(W0, X, y, lam, steps=150, lr=0.01):
    W = torch.tensor(W0, requires_grad=True)
    W0t = torch.tensor(W0)
    Xt, yt = torch.tensor(X), torch.tensor(y)
    opt = torch.optim.Adam([W], lr=lr)
    for _ in range(steps):
        Wn = W / W.norm(dim=1, keepdim=True)
        loss = torch.nn.functional.cross_entropy(100 * Xt @ Wn.T, yt) + lam * ((W - W0t) ** 2).sum()
        opt.zero_grad(); loss.backward(); opt.step()
    with torch.no_grad():
        return (W / W.norm(dim=1, keepdim=True)).numpy()


def tip_logits(W0, F, yF, Xq, beta, gamma, C):
    Y = np.eye(C, dtype=np.float32)[yF]
    A = np.exp(-gamma * (1 - Xq @ F.T))
    return 100 * Xq @ W0.T + beta * A @ Y


def run_method(meth, hp, W0, tr, te, y, C):
    X, yt = EMB[tr], y[tr]
    if meth == "ZS":
        return 100 * EMB[te] @ W0.T
    if meth == "PROTO":
        return 100 * EMB[te] @ fit_proto(W0, X, yt, hp).T
    if meth == "PROBE":
        return 100 * EMB[te] @ fit_probe(W0, X, yt, hp).T
    if meth == "TIP":
        return tip_logits(W0, X, yt, EMB[te], hp[0], hp[1], C)


def evaluate(meth, hp, W0, labels, y, k=None, seeds=(0,), protocols=("public", "ipad", "loso")):
    C = len(labels)
    res = collections.defaultdict(list)
    for s in seeds:
        rng = np.random.default_rng(100 + s)
        pred = np.empty(N, dtype=object)
        if "public" in protocols:
            for f in range(5):
                tr = sample(pub_idx[fold[pub_idx] != f], y, k, rng)
                te = pub_idx[fold[pub_idx] == f]
                pred[te] = labels[run_method(meth, hp, W0, tr, te, y, C).argmax(1)]
        ip = np.where(is_ipad)[0]
        if "ipad" in protocols:
            tr = sample(pub_idx, y, k, rng)
            pred[ip] = labels[run_method(meth, hp, W0, tr, ip, y, C).argmax(1)]
            m = metrics(pred)
            res["pub"].append(m["pub"]); res["ipad"].append(m["ipad"]); res["nP"].append(m["nP"]); res["nR"].append(m["nR"])
        if "loso" in protocols:
            p2 = pred.copy()
            trp = sample(pub_idx, y, k, rng)
            for sc in np.unique(scan[ip]):
                te = ip[scan[ip] == sc]
                trl = np.concatenate([trp, ip[(scan[ip] != sc) & (y[ip] >= 0)]])
                p2[te] = labels[run_method(meth, hp, W0, trl, te, y, C).argmax(1)]
            m = metrics(p2)
            res["L_ipad"].append(m["ipad"]); res["L_nP"].append(m["nP"]); res["L_nR"].append(m["nR"])
    return {k_: float(np.nanmean(v)) for k_, v in res.items()}


def f(x):
    return "n/a" if x != x else f"{100 * x:.1f}"


if __name__ == "__main__":
    out = []
    w = out.append
    for which in ("V0", "V4"):
        names, labels, W0, Cd = text_set(which)
        y = row_class(names, labels, W0)
        w(f"\n### Prompt set {which}: hyper-parameter sweep, all public shots (public = grouped 5-fold CV)\n")
        w("| Method | hp | Public % | iPad % | none P | none R | iPad+LOSO % | LOSO none P | LOSO none R |")
        w("|---|---|---|---|---|---|---|---|---|")
        grid = [("ZS", None)] + [("PROTO", a) for a in (0.9, 0.8, 0.7, 0.6, 0.5, 0.3, 0.0)] + \
               [("PROBE", l) for l in (1.0, 0.1, 0.01, 0.001)] + \
               [("TIP", (b, g)) for b in (1, 3, 10) for g in (2, 5, 10)]
        best = {}
        for meth, hp in grid:
            r = evaluate(meth, hp, W0, labels, y)
            w(f"| {meth} | {hp} | {f(r['pub'])} | {f(r['ipad'])} | {f(r['nP'])} | {f(r['nR'])} | {f(r['L_ipad'])} | {f(r['L_nP'])} | {f(r['L_nR'])} |")
            if meth not in best or r["pub"] > best[meth][1]["pub"]:
                best[meth] = (hp, r)
        w("\nBest hp per method by public CV: " + ", ".join(f"{m}={v[0]}" for m, v in best.items()) + "\n")
        w(f"#### Shots per class ({which}; mean of 5 seeds; hp = best-by-public above)\n")
        w("| Method | k | Public % | iPad % | none P | none R | iPad+LOSO % | LOSO none P | LOSO none R |")
        w("|---|---|---|---|---|---|---|---|---|")
        for meth in ("PROTO", "PROBE", "TIP"):
            for k in (1, 2, 4, 8, 16, None):
                r = evaluate(meth, best[meth][0], W0, labels, y, k=k, seeds=range(5) if k else (0,))
                w(f"| {meth} | {k or 'all'} | {f(r['pub'])} | {f(r['ipad'])} | {f(r['nP'])} | {f(r['nR'])} | {f(r['L_ipad'])} | {f(r['L_nP'])} | {f(r['L_nR'])} |")
        print("\n".join(out), flush=True)
    open(f"{HERE}/fewshot_results.md", "w").write("\n".join(out))

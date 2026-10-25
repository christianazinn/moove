"""Follow-ups: in-domain (iPad, leave-one-scan-out) probe variants, none-bias calibration, label merges,
LiDAR-height rule for table vs storage, and the final exported adapter.

Run: /tmp/claude-501/venv-eval/bin/python -I fewshot2.py
"""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research2")
from fewshot import *

geom = json.load(open(f"{HERE}/geom.json"))
H = np.array([(geom.get(r["path"]) or {}).get("dims", [np.nan] * 3)[1] for r in rows], dtype=float)
FP = np.array([np.prod(np.array((geom.get(r["path"]) or {}).get("dims", [np.nan] * 3))[[0, 2]]) for r in rows], dtype=float)

MERGES = {
    "none": {},
    "M1 bag+backpack": {"backpack": "bag"},
    "M2 M1 + TV+monitor=screen": {"backpack": "bag", "television": "screen", "monitor": "screen"},
    "M3 M2 + shelf->storage": {"backpack": "bag", "television": "screen", "monitor": "screen", "shelf": "storage"},
    "M4 M3 + suitcase->bag": {"backpack": "bag", "television": "screen", "monitor": "screen", "shelf": "storage", "suitcase": "bag"},
}


def mfun(d):
    return lambda x: d.get(x, x)


def merged_metrics(pred, d):
    m = metrics(pred, merge=mfun(d))
    return m


def loso_logits(meth, hp, W0, y, C, k, rng, ipad_w=1.0):
    """iPad rows: logits from a model trained on k public shots/class + other scans' iPad photos."""
    ip = np.where(is_ipad)[0]
    L = np.zeros((N, C), np.float32)
    trp = sample(pub_idx, y, k, rng) if k != 0 else np.array([], int)
    for sc in np.unique(scan[ip]):
        te = ip[scan[ip] == sc]
        tri = ip[(scan[ip] != sc) & (y[ip] >= 0)]
        tr = np.concatenate([trp, np.repeat(tri, int(ipad_w))]).astype(int)
        L[te] = run_method(meth, hp, W0, tr, te, y, C)
    return L


def calibrated_bias(L, labels, bs=np.arange(-3, 4.01, 0.5)):
    """none-logit bias per held-out scan, chosen on the OTHER scans' (out-of-scan) predictions to maximise
    iPad top-1 + none F1. Returns predictions for iPad rows."""
    isnone = np.array([l == "none" or l in FIXTURE for l in labels])
    pred = np.empty(N, dtype=object)
    ip = np.where(is_ipad)[0]
    chosen = []
    for sc in np.unique(scan[ip]):
        oth = is_ipad & (scan != sc)
        def score(b):
            p = labels[(L + b / 100 * 100 * isnone).argmax(1)].astype(object)
            a = np.mean([ipad_view(q) == canon(g) for q, g in zip(p[oth & ipad_obj], gt[oth & ipad_obj])])
            pn = np.array([ipad_view(q) == "none" for q in p]) & oth & ipad_scored
            tp = (pn & ipad_none).sum(); P_ = tp / max(pn.sum(), 1); R_ = tp / max((oth & ipad_none).sum(), 1)
            return a + (2 * P_ * R_ / max(P_ + R_, 1e-9))
        b = max(bs, key=score)
        chosen.append(b)
        te = is_ipad & (scan == sc)
        pred[te] = labels[(L[te] + b * isnone).argmax(1)]
    return pred, chosen


if __name__ == "__main__":
    out = []
    w = out.append
    names, labels, W0, Cd = text_set("V4")
    y = row_class(names, labels, W0)
    C = len(labels)
    ip = np.where(is_ipad)[0]
    rng = np.random.default_rng(7)

    # ---------------- A: in-domain LOSO variants ----------------
    w("### A. Leave-one-scan-out with own iPad photos (prompt set V4; iPad rows only; 10 scans)\n")
    w("| Method | public shots/class | iPad weight | iPad top-1 % | none P % | none R % |\n|---|---|---|---|---|---|")
    LL = {}
    for meth, hp in (("PROBE", 1.0), ("PROBE", 0.1), ("PROBE", 0.01), ("PROTO", 0.6), ("TIP", (1, 10))):
        for k in (0, 1, 4, None):
            for iw in ((1, 3) if meth == "PROBE" else (1,)):
                L = loso_logits(meth, hp, W0, y, C, k, np.random.default_rng(7), iw)
                p = np.empty(N, dtype=object); p[ip] = labels[L[ip].argmax(1)]
                p[is_pub] = "x"
                m = metrics(p)
                LL[(meth, hp, k, iw)] = L
                w(f"| {meth} {hp} | {'all' if k is None else k} | {iw} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])} |")
    w("")
    # ---------------- B: bias calibration ----------------
    w("### B. none-bias chosen per held-out scan on the other scans (iPad only)\n")
    w("| Model | iPad top-1 % | none P % | none R % | biases chosen |\n|---|---|---|---|---|")
    zs_L = np.zeros((N, C), np.float32); zs_L[:] = 100 * EMB @ W0.T
    probe_pub = 100 * EMB @ fit_probe(W0, EMB[pub_idx], y[pub_idx], 1.0).T
    cands = {"ZS V4": zs_L, "PROBE lam=1, public only": probe_pub,
             "PROBE lam=1, public all + LOSO iPad": LL[("PROBE", 1.0, None, 1)],
             "PROBE lam=0.1, public k=1 + LOSO iPad": LL[("PROBE", 0.1, 1, 1)],
             "PROBE lam=0.1, public all + LOSO iPad x3": LL[("PROBE", 0.1, None, 3)]}
    BP = {}
    for nm, L in cands.items():
        p, ch = calibrated_bias(L, labels)
        p[is_pub] = "x"
        BP[nm] = p
        m = metrics(p)
        w(f"| {nm} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])} | {sorted(collections.Counter(ch).items())} |")
    w("")
    # ---------------- C: merges ----------------
    w("### C. Label merges (both truth and prediction mapped; public = ZS / 5-fold probe, iPad as stated)\n")
    pub_zs = labels[zs_L.argmax(1)].astype(object)
    pr_cv = np.empty(N, dtype=object)
    for fo in range(5):
        tr = pub_idx[fold[pub_idx] != fo]; te = pub_idx[fold[pub_idx] == fo]
        pr_cv[te] = labels[(EMB[te] @ fit_probe(W0, EMB[tr], y[tr], 1.0).T).argmax(1)]
    pr_cv[ip] = labels[probe_pub[ip].argmax(1)]
    loso_p = np.empty(N, dtype=object); loso_p[:] = pr_cv
    loso_p[ip] = labels[LL[("PROBE", 0.1, 1, 1)][ip].argmax(1)]
    base_p = Z["labels"][Z["logits"].argmax(1)].astype(object)
    w("| Merge | V0 ZS pub | V0 ZS iPad | V4 ZS pub | V4 ZS iPad | probe(lam=1) pub CV | probe iPad | LOSO probe iPad |\n|---|---|---|---|---|---|---|---|")
    for mn, d in MERGES.items():
        a, b, c = merged_metrics(base_p, d), merged_metrics(pub_zs, d), merged_metrics(pr_cv, d)
        e = merged_metrics(loso_p, d)
        w(f"| {mn} | {f(a['pub'])} | {f(a['ipad'])} | {f(b['pub'])} | {f(b['ipad'])} | {f(c['pub'])} | {f(c['ipad'])} | {f(e['ipad'])} |")
    w("")
    # ---------------- D: LiDAR height rule ----------------
    w("### D. iPad geometry for table / storage / shelf / chair (and anything predicted as one)\n")
    w("| photo | truth | object | box W x H x D (m) | V0 ZS | V4 ZS | 2nd choice V4 |\n|---|---|---|---|---|---|---|")
    order = np.argsort(-zs_L, 1)
    furn = {"table", "storage", "shelf", "chair"}
    for i in ip:
        if gt[i] in furn or base_p[i] in furn or pub_zs[i] in furn:
            g = geom.get(rows[i]["path"]) or {}
            dd = g.get("dims")
            ds = "x".join(f"{v:.2f}" for v in dd) if dd else "n/a"
            sec = next(labels[j] for j in order[i] if labels[j] != pub_zs[i])
            w(f"| {os.path.basename(rows[i]['path'])[:28]} | {gt[i]} | {rows[i]['true_object'][:30]} | {ds} | {base_p[i]} | {pub_zs[i]} | {sec} |")
    w("")

    def height_rule(pred, L, hmax_table=0.9):
        """If the classifier says table or storage and table/storage are its top-2 Moove labels, choose by
        box height: H > hmax_table -> storage, H <= hmax_table and footprint >= 0.3 m^2 -> table."""
        p = pred.copy()
        for i in ip:
            if p[i] not in ("table", "storage") or not np.isfinite(H[i]):
                continue
            top = []
            for j in np.argsort(-L[i]):
                if labels[j] not in top:
                    top.append(labels[j])
                if len(top) == 2:
                    break
            if set(top) != {"table", "storage"}:
                continue
            if H[i] > hmax_table:
                p[i] = "storage"
            elif FP[i] >= 0.3:
                p[i] = "table"
        return p
    w("Height rule (table vs storage, only when those are the top-2 labels):\n")
    w("| Model | before iPad % | after iPad % | changed photos |\n|---|---|---|---|")
    for nm, pred, L in (("V4 ZS", pub_zs, zs_L), ("LOSO probe", loso_p, LL[("PROBE", 0.1, 1, 1)])):
        p2 = height_rule(pred, L)
        ch = [(gt[i], pred[i], p2[i]) for i in ip if p2[i] != pred[i]]
        w(f"| {nm} | {f(metrics(pred)['ipad'])} | {f(metrics(p2)['ipad'])} | {ch} |")
    w("")
    print("\n".join(out))
    open(f"{HERE}/fewshot2_results.md", "w").write("\n".join(out))

    # ---------------- export adapters ----------------
    W_pub = fit_probe(W0, EMB[pub_idx], y[pub_idx], 1.0)
    allr = np.where(y >= 0)[0]
    W_all = fit_probe(W0, EMB[allr], y[allr], 0.1)
    np.save(f"{HERE}/W_text_V4.npy", W0.astype(np.float16))
    np.save(f"{HERE}/W_probe_public_lam1.npy", W_pub.astype(np.float16))
    np.save(f"{HERE}/W_probe_public+ipad_lam0.1.npy", W_all.astype(np.float16))
    json.dump({"classes": names, "labels": list(labels), "logit_scale": 100.0,
               "usage": "logits = 100 * normalize(image_embedding) @ W.T ; label = labels[argmax]; "
                        "label 'none' or radiator/shower curtain/towel rack => not a movable object",
               "prompts": {k: v[1] for k, v in Cd.items()}, "templates": PR.BASE_T},
              open(f"{HERE}/adapter_classes.json", "w"), indent=1)
    print("exported", W0.shape)

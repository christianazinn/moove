"""LiDAR size prior: penalise class logits whose typical real-world size range the scanned box violates.

Ranges are written from general furniture knowledge (NOT fitted to the iPad boxes). L = longest horizontal
side, H = height (m). Penalty = lam * sum(max(0, log(lo/x), log(x/hi))) added (negatively) to the logit.
Run: /tmp/claude-501/venv-eval/bin/python -I size_prior.py
"""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research2")
from fewshot2 import *

RANGE = {  # label: (L lo, L hi, H lo, H hi)
    "bed": (1.7, 2.4, 0.2, 2.0), "sofa": (1.2, 3.2, 0.5, 1.2), "table": (0.5, 2.6, 0.35, 1.1),
    "storage": (0.3, 2.6, 0.4, 2.5), "chair": (0.35, 1.0, 0.6, 1.3), "lamp": (0.15, 0.7, 0.25, 2.0),
    "television": (0.55, 2.0, 0.3, 1.3), "monitor": (0.3, 0.9, 0.2, 0.7), "laptop": (0.25, 0.45, 0.01, 0.35),
    "refrigerator": (0.45, 1.0, 0.45, 2.0), "toilet": (0.35, 0.8, 0.6, 0.9), "bathtub": (1.2, 1.9, 0.35, 0.7),
    "sink": (0.35, 1.2, 0.1, 0.6), "box": (0.2, 0.8, 0.1, 0.8), "backpack": (0.2, 0.5, 0.25, 0.6),
    "bag": (0.25, 0.9, 0.15, 0.5), "suitcase": (0.35, 0.85, 0.2, 0.85), "trash can": (0.2, 0.6, 0.25, 1.0),
    "bicycle": (1.2, 2.0, 0.6, 1.2), "microwave": (0.4, 0.6, 0.2, 0.4),
}


def size_pen(labels, i):
    g = geom.get(rows[i]["path"]) if is_ipad[i] else None
    pen = np.zeros(len(labels), np.float32)
    if not g:
        return pen
    W_, H_, D_ = g["dims"]
    L_ = max(W_, D_)
    for j, l in enumerate(labels):
        if l in RANGE:
            a, b, c, d = RANGE[l]
            pen[j] = max(0, np.log(a / L_), np.log(L_ / b)) + max(0, np.log(c / max(H_, 1e-3)), np.log(H_ / d))
    return pen


if __name__ == "__main__":
    names, labels, W0, Cd = text_set("V4")
    y = row_class(names, labels, W0)
    C = len(labels)
    ip = np.where(is_ipad)[0]
    PEN = np.zeros((N, C), np.float32)
    for i in ip:
        PEN[i] = size_pen(labels, i)
    zs_L = 100 * EMB @ W0.T
    loso_L = loso_logits("PROBE", 0.1, W0, y, C, 1, np.random.default_rng(7))
    base_L = Z["logits"]
    out = ["### E. Size prior on iPad (penalty lam per log-unit of size violation)\n",
           "| Model | lam | iPad top-1 % | none P % | none R % | M3-merged iPad % |", "|---|---|---|---|---|---|"]
    notes = []
    for nm, L, lab in (("V0 ZS", base_L, Z["labels"]), ("V4 ZS", zs_L, labels), ("LOSO probe lam=0.1 k=1", loso_L, labels)):
        P0 = PEN if lab is labels else np.stack([size_pen(lab, i) if is_ipad[i] else np.zeros(len(lab)) for i in range(N)])
        for lam in (0, 1, 2, 4, 8):
            p = np.empty(N, dtype=object); p[:] = "x"
            p[ip] = np.asarray(lab)[(L[ip] - lam * P0[ip]).argmax(1)]
            m = metrics(p); mm = merged_metrics(p, MERGES["M3 M2 + shelf->storage"])
            out.append(f"| {nm} | {lam} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])} | {f(mm['ipad'])} |")
        if nm == "V4 ZS":
            p0 = labels[L[ip].argmax(1)]; p4 = labels[(L[ip] - 4 * PEN[ip]).argmax(1)]
            notes.append("\nV4 ZS changes at lam=4 (truth: before -> after): " + "; ".join(
                f"{gt[i]}: {a}->{b}" for i, a, b in zip(ip, p0, p4) if a != b) + "\n")
    out += notes
    print("\n".join(out))
    open(f"{HERE}/size_prior_results.md", "w").write("\n".join(out))

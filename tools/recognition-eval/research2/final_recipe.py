"""Final recipe numbers: V4 prompts -> text-anchored probe (lam=1) on public crops -> optional none bias -> merges.
Public = grouped 5-fold CV; iPad = model trained on all public crops. Bias chosen leave-one-room-out on iPad."""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research2")
import fewshot2
from loro import ROOM, room
from fewshot2 import *
fewshot2.scan = room
names, labels, W0, Cd = text_set("V4")
y = row_class(names, labels, W0); ip = np.where(is_ipad)[0]
isnone = np.array([l == "none" or l in FIXTURE for l in labels])
L = np.zeros((N, len(labels)), np.float32)
for fo in range(5):
    tr = pub_idx[fold[pub_idx] != fo]; te = pub_idx[fold[pub_idx] == fo]
    L[te] = 100 * EMB[te] @ fit_probe(W0, EMB[tr], y[tr], 1.0).T
Wp = fit_probe(W0, EMB[pub_idx], y[pub_idx], 1.0)
L[ip] = 100 * EMB[ip] @ Wp.T
pb, ch = fewshot2.calibrated_bias(L, labels)
print("LORO-chosen biases:", collections.Counter(ch))
base = Z["labels"][Z["logits"].argmax(1)].astype(object)
zsL = 100 * EMB @ W0.T
print("| Recipe | merge | Public top-1 % | iPad top-1 % | none P % | none R % |\n|---|---|---|---|---|---|")
for nm, P_ in (("V0 ZS (current)", base), ("V4 ZS", labels[zsL.argmax(1)].astype(object)),
               ("V4 + probe lam=1", labels[L.argmax(1)].astype(object)),
               ("V4 + probe lam=1 + none bias +1", labels[(L + 1.0 * isnone).argmax(1)].astype(object))):
    for mn in ("none", "M1 bag+backpack", "M3 M2 + shelf->storage"):
        m = merged_metrics(P_, MERGES[mn])
        print(f"| {nm} | {mn} | {f(m['pub'])} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])} |")

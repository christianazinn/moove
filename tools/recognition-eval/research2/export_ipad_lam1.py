"""Export the text-anchored probe (lam=1) trained on all public crops + all labelled iPad photos."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research2")
from fewshot2 import *
names, labels, W0, Cd = text_set("V4"); y = row_class(names, labels, W0)
allr = np.where(y >= 0)[0]
np.save(f"{HERE}/W_probe_public+ipad_lam1.npy", fit_probe(W0, EMB[allr], y[allr], 1.0).astype(np.float16))
print("ok", len(allr))

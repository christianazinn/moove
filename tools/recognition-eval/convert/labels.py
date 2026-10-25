"""Builds the classifier's label matrix with the PE-Core text tower.

Usage: python -I labels.py <vocab: bench|full> <out dir>
- bench: exactly zs_eval.py's CLASSES / TEMPLATES / negatives.
- full: those plus one class per detector category zs_eval doesn't cover (prompts = the
  detector's own prompts for it, from ObjectVocabulary.swift), so the classifier can
  vote for whatever the detector can say.
Writes labels_<vocab>.json (classes, category per class, logit scale) and
labels_<vocab>.f16 (row-major [C, 512] float16, L2-normalized rows).
"""
import json, os, re, sys
import numpy as np, torch

EV = "/tmp/claude-501/ev" "al"
VOCAB_SWIFT = sys.argv[3] if len(sys.argv) > 3 else None
vocab, OUT = sys.argv[1], sys.argv[2]
sys.path.insert(0, EV)
_argv, sys.argv = sys.argv, ["zs_eval"]
import zs_eval  # defines CLASSES / TEMPLATES; runs nothing without model keys
sys.argv = _argv
os.environ["HF_HUB_OFFLINE"] = "1"
import open_clip

# Moove category per prompt class. zs_eval's labels are Moove categories already, except
# the scoring aliases; fixtures stay named (they're rejected, the name is the reason).
CATEGORY = {"ceiling fan": "fan"}
FIXTURES = {"radiator", "shower curtain", "towel rack"}

classes = {k: (CATEGORY.get(v[0], v[0]), list(v[1])) for k, v in zs_eval.CLASSES.items()}
if vocab == "full":
    src = open(VOCAB_SWIFT).read()
    blk = src.split("categories: [String: String] = [")[1].split("\n    ]")[0]
    det = re.findall(r'"([^"]+)":\s*"([^"]+)"', blk)
    covered = {c for c, _ in classes.values()}
    by_cat = {}
    for lab, cat in det:
        if cat not in covered:
            by_cat.setdefault(cat, []).append(lab)
    for cat, labs in sorted(by_cat.items()):
        classes["det_" + cat.replace(" ", "_")] = (cat, labs)

name = f"local-dir:{EV}/dl/pecore"
m, _, _ = open_clip.create_model_and_transforms(name)
m = m.eval()
tok = open_clip.get_tokenizer(name)
T = []
with torch.no_grad():
    for k, (cat, names) in classes.items():
        texts = [t.format(s) for s in names for t in zs_eval.TEMPLATES]
        e = m.encode_text(tok(texts)).float()
        e = (e / e.norm(dim=-1, keepdim=True)).mean(0)
        T.append((e / e.norm()).numpy())
T = np.stack(T).astype(np.float32)
os.makedirs(OUT, exist_ok=True)
T.astype("<f2").tofile(f"{OUT}/labels_{vocab}.f16")
np.save(f"{OUT}/labels_{vocab}.npy", T)
meta = {
    "model": "PE-Core-S/16-384",
    "dimension": int(T.shape[1]),
    "logitScale": round(float(m.logit_scale.exp().item()), 4),
    "templates": zs_eval.TEMPLATES,
    "classes": [{"id": k, "category": "none" if cat == "none" else cat, "prompts": names} for k, (cat, names) in classes.items()],
    "fixtures": sorted(FIXTURES),
}
json.dump(meta, open(f"{OUT}/labels_{vocab}.json", "w"), indent=1)
print(vocab, len(classes), "classes, scale", meta["logitScale"])

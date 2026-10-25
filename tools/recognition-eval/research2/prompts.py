"""Prompt-engineering variants for PE-Core-S/16-384, re-scored on the saved image embeddings.

Run: /tmp/claude-501/venv-eval/bin/python -I prompts.py  -> prints markdown, writes prompts_best.json
"""
import sys, json, copy, collections
sys.path.insert(0, "/tmp/claude-501/eval/research2")
from common import *

src = open(f"{EVAL}/zs_eval.py").read()
ns = {}
exec(src[src.index("CLASSES = {"):src.index("names = list(CLASSES)")], ns)
BASE, BASE_T = ns["CLASSES"], ns["TEMPLATES"]

# ---- positive-class synonym upgrades (written from general knowledge of the class, not from iPad images)
SYN = {
    "backpack": ["backpack", "rucksack", "backpack with shoulder straps", "school backpack"],
    "bag": ["duffel bag", "gym bag", "travel duffel bag", "handbag", "tote bag"],
    "table": ["table", "wooden table", "dining table", "coffee table", "kitchen table", "side table"],
    "desk": ["desk", "office desk", "computer desk", "writing desk"],
    "bookshelf": ["bookshelf", "bookcase full of books", "tall bookcase"],
    "shelf": ["wall shelf", "floating shelf on a wall", "shelving unit", "shelf"],
    "cabinet": ["cabinet", "cupboard", "filing cabinet", "kitchen cabinet"],
    "nightstand": ["nightstand", "bedside table"],
    "chair": ["chair", "armchair", "folding chair", "dining chair", "wooden chair"],
    "monitor": ["computer monitor", "computer monitor on a desk", "desktop computer screen"],
    "television": ["television", "tv", "flat screen tv", "tv on a tv stand", "wall-mounted tv"],
    "mirror": ["mirror", "wall mirror", "full-length mirror"],
    "trash_can": ["trash can", "waste bin", "garbage can", "wastebasket"],
    "sink": ["sink", "bathroom sink", "kitchen sink", "washbasin"],
    "rug": ["rug", "carpet", "bath mat", "doormat"],
    "box": ["cardboard box", "moving box", "stack of cardboard boxes"],
    "dolly_cart": ["hand truck", "furniture dolly", "rolling cart", "moving dolly"],
    "heater": ["space heater", "portable electric heater", "fan heater"],
    "sofa": ["sofa", "couch", "sofa bed"],
    "plant": ["potted plant", "houseplant", "plant in a flower pot"],
    "ottoman": ["ottoman", "footstool", "pouf"],
    "suitcase": ["suitcase", "rolling luggage"],
    "lamp": ["floor lamp", "table lamp", "desk lamp", "lamp"],
}
# ---- negatives requested by the brief (several were chosen after seeing the iPad `none` photos -> test-informed)
NEG_BRIEF = {
    "neg_wall": ["wall", "blank wall"],
    "neg_door": ["door", "doorway"],
    "neg_doorframe": ["door frame"],
    "neg_window": ["window"],
    "neg_curtain": ["curtain"],
    "neg_plastic": ["plastic sheeting", "black plastic sheet on the floor"],
    "neg_clothes": ["pile of clothes"],
    "neg_panel": ["electrical panel", "fuse box"],
    "neg_switch": ["light switch", "power outlet"],
    "neg_pipe": ["pipe"],
    "neg_ceiling": ["ceiling"],
    "neg_floor": ["floor"],
    "neg_corner": ["empty corner of a room"],
}
# ---- extra negatives that match specific iPad `none` photos (strongly test-informed; report separately)
NEG_IPAD = {
    "neg_broom": ["broom", "mop"],
    "neg_tripod": ["light stand", "tripod"],
    "neg_board": ["whiteboard", "blackboard"],
    "neg_pole": ["structural column", "pole"],
    "neg_extinguisher": ["fire extinguisher"],
}
# ---- generic "not a whole object" negatives (not tied to iPad photos)
NEG_GENERIC = {
    "neg_blur": ["blurry photo", "dark blurry photo"],
    "neg_texture": ["close-up of a surface texture"],
    "neg_clutter": ["clutter"],
}
T_MORE = ["a photo of a {}.", "a photo of a {} in a room.", "a cropped photo of a {}.", "a close-up photo of a {}.",
          "a blurry photo of a {}.", "a photo of a {} in a home.", "a low-light photo of a {}.", "a photo of a {} indoors."]
T_ONE = ["a photo of a {}."]


def build(syn=False, neg=None, keep_old_neg=True, only=None):
    C = copy.deepcopy(BASE)
    if syn:
        for k, v in SYN.items():
            if only is None or k in only:
                C[k] = (C[k][0], v)
    if not keep_old_neg:
        C = {k: v for k, v in C.items() if not k.startswith("neg_")}
    for d in (neg or []):
        for k, v in d.items():
            C[k] = ("none", v)
    return C


def run(C, T):
    names, labels, W = class_weights(C, T)
    pred, lg = predict(W, labels)
    return pred, lg, names, labels, W


def conf(pred, mask, view=canon, k=6):
    cc = collections.Counter((g, view(p)) for g, p in zip(gt[mask], pred[mask]) if canon(g) != view(p))
    return "; ".join(f"{a}->{b} {n}" for (a, b), n in cc.most_common(k))


VARIANTS = {
    "V0 baseline (zs_eval.py prompts)": (build(), BASE_T),
    "V0a baseline, 1 template": (build(), T_ONE),
    "V0b baseline, 8 templates": (build(), T_MORE),
    "V1 synonyms": (build(syn=True), BASE_T),
    "V1b synonyms, 8 templates": (build(syn=True), T_MORE),
    "V2 brief negatives": (build(neg=[NEG_BRIEF]), BASE_T),
    "V2b brief + generic negatives": (build(neg=[NEG_BRIEF, NEG_GENERIC]), BASE_T),
    "V2c brief + generic + iPad-informed negatives": (build(neg=[NEG_BRIEF, NEG_GENERIC, NEG_IPAD]), BASE_T),
    "V3 synonyms + brief negatives": (build(syn=True, neg=[NEG_BRIEF]), BASE_T),
    "V3b synonyms + brief + generic negatives": (build(syn=True, neg=[NEG_BRIEF, NEG_GENERIC]), BASE_T),
    "V3c synonyms + brief + generic + iPad-informed neg": (build(syn=True, neg=[NEG_BRIEF, NEG_GENERIC, NEG_IPAD]), BASE_T),
    "V3d = V3b, 8 templates": (build(syn=True, neg=[NEG_BRIEF, NEG_GENERIC]), T_MORE),
}

if __name__ == "__main__":
    out = []
    w = out.append
    w("### Prompt variants (PE-Core-S/16-384, saved image embeddings, logit scale 100)\n")
    w(HDR)
    res = {}
    for name, (C, T) in VARIANTS.items():
        pred, lg, names, labels, W = run(C, T)
        res[name] = (pred, lg, names, labels, W, C, T)
        w(f"| {name} ({len(C)} cls) | {fmt(metrics(pred))} |")
    w("")
    # per-synonym ablation: apply one SYN entry at a time on top of V2b
    w("### One-class synonym ablation on top of V2b (delta vs V2b, pp)\n")
    w("| class changed | public | iPad | none P | none R |\n|---|---|---|---|---|")
    ref = metrics(res["V2b brief + generic negatives"][0])
    for k in SYN:
        p, *_ = run(build(syn=True, neg=[NEG_BRIEF, NEG_GENERIC], only={k}), BASE_T)
        m = metrics(p)
        w(f"| {k} | " + " | ".join(f"{100 * (m[x] - ref[x]):+.1f}" for x in ("pub", "ipad", "nP", "nR")) + " |")
    w("")
    w("### Confusions\n")
    for name in ("V0 baseline (zs_eval.py prompts)", "V3b synonyms + brief + generic negatives"):
        p = res[name][0]
        w(f"- **{name}** public: {conf(p, is_pub)}")
        w(f"  - iPad: {conf(p, ipad_scored, ipad_view)}")
    # none-logit bias sweep (adds b to every none-class logit), on V3b
    w("\n### none-bias sweep on V3b (b added to every `none` prompt logit; positive = more rejection)\n")
    w(HDR)
    pred, lg, names, labels, W, C, T = res["V3b synonyms + brief + generic negatives"]
    for b in (-2, -1, 0, 1, 2, 3, 4):
        l2 = lg + b * (labels == "none")
        w(f"| b={b:+d} | {fmt(metrics(labels[l2.argmax(1)].astype(object)))} |")
    print("\n".join(out))
    open(f"{HERE}/prompts_results.md", "w").write("\n".join(out))
    for key, fn in (("V3b synonyms + brief + generic negatives", "prompts_V3b.json"),
                    ("V3c synonyms + brief + generic + iPad-informed neg", "prompts_V3c.json")):
        C, T = res[key][5], res[key][6]
        json.dump({"templates": T, "classes": {k: {"label": v[0], "names": v[1]} for k, v in C.items()}},
                  open(f"{HERE}/{fn}", "w"), indent=1)

"""Zero-shot (text-prompt) classification + image embeddings for the bench.

Usage (run with the eval venv, isolated):
  /tmp/claude-501/venv-eval/bin/python -I zs_eval.py <model-key> [<model-key> ...]
model keys: siglip-so400m (HF cache), clip-l14 (HF cache), pecore-s16 (open_clip, local
weights in dl/pecore), siglip2-b16 (open_clip hf-hub, only if downloaded).
Writes zs_<key>.npz: paths, prompt classes, class->Moove label, logits [N, C],
image embeddings [N, D], per-image encoder ms.
"""
import json, sys, time, os
import numpy as np, torch
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = "/tmp/claude-501/bench"
rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
paths = [r["path"] for r in rows]

# prompt class -> (Moove label, [names]). Bench classes + the few iPad-only categories
# the detector also knows, + generic "not an object" negatives (label none).
CLASSES = {
    "backpack": ("backpack", ["backpack"]),
    "bag": ("bag", ["duffel bag", "handbag", "tote bag"]),
    "bathtub": ("bathtub", ["bathtub"]),
    "bed": ("bed", ["bed", "bunk bed"]),
    "bicycle": ("bicycle", ["bicycle"]),
    "box": ("box", ["cardboard box", "moving box"]),
    "dolly_cart": ("cart", ["hand truck", "furniture dolly", "rolling cart"]),
    "ceiling_fan": ("ceiling fan", ["ceiling fan"]),
    "chair": ("chair", ["chair", "armchair", "folding chair"]),
    "office_chair": ("chair", ["office chair"]),
    "fan": ("fan", ["electric fan", "standing fan"]),
    "guitar": ("guitar", ["guitar"]),
    "heater": ("heater", ["space heater", "portable electric heater"]),
    "ironing_board": ("ironing board", ["ironing board"]),
    "ladder": ("ladder", ["ladder", "step ladder"]),
    "lamp": ("lamp", ["floor lamp", "table lamp", "desk lamp"]),
    "laptop": ("laptop", ["laptop"]),
    "microwave": ("microwave", ["microwave oven"]),
    "mirror": ("mirror", ["mirror"]),
    "monitor": ("monitor", ["computer monitor"]),
    "ottoman": ("ottoman", ["ottoman", "footstool"]),
    "plant": ("plant", ["potted plant", "houseplant"]),
    "radiator": ("radiator", ["radiator"]),
    "refrigerator": ("refrigerator", ["refrigerator", "mini fridge"]),
    "rug": ("rug", ["rug", "carpet"]),
    "scooter": ("scooter", ["kick scooter", "electric scooter"]),
    "shelf": ("shelf", ["wall shelf"]),
    "shower_curtain": ("shower curtain", ["shower curtain"]),
    "sink": ("sink", ["sink"]),
    "sofa": ("sofa", ["sofa", "couch"]),
    "bookshelf": ("storage", ["bookshelf"]),
    "cabinet": ("storage", ["cabinet"]),
    "dresser": ("storage", ["dresser", "chest of drawers"]),
    "nightstand": ("storage", ["nightstand"]),
    "stroller": ("stroller", ["baby stroller"]),
    "suitcase": ("suitcase", ["suitcase"]),
    "desk": ("table", ["desk"]),
    "table": ("table", ["table"]),
    "television": ("television", ["television", "tv"]),
    "toilet": ("toilet", ["toilet"]),
    "towel_rack": ("towel rack", ["towel rack"]),
    "trash_can": ("trash can", ["trash can"]),
    "vacuum": ("vacuum", ["vacuum cleaner"]),
    "washing_machine": ("washerDryer", ["washing machine"]),
    "yoga_mat": ("yoga mat", ["yoga mat"]),
    # iPad-only categories the detector vocabulary also has
    "art": ("art", ["framed picture", "painting"]),
    "bean_bag": ("bean bag", ["bean bag chair"]),
    "clothes_rack": ("clothes rack", ["clothes rack"]),
    "coat_rack": ("coat rack", ["coat rack"]),
    # generic negatives (not tuned to individual iPad images)
    "neg_wall": ("none", ["wall", "blank wall"]),
    "neg_door": ("none", ["door", "doorway"]),
    "neg_window": ("none", ["window"]),
    "neg_floor": ("none", ["floor"]),
    "neg_ceiling": ("none", ["ceiling"]),
    "neg_corner": ("none", ["empty corner of a room"]),
    "neg_clothes": ("none", ["pile of clothes"]),
    "neg_curtain": ("none", ["curtain"]),
}
TEMPLATES = ["a photo of a {}.", "a photo of a {} in a room.", "a cropped photo of a {}."]
names = list(CLASSES)
dev = "mps" if torch.backends.mps.is_available() else "cpu"


def load(key):
    if key in ("siglip-so400m", "clip-l14"):
        from transformers import AutoModel, AutoProcessor
        repo = {"siglip-so400m": "google/siglip-so400m-patch14-384", "clip-l14": "openai/clip-vit-large-patch14"}[key]
        os.environ["HF_HUB_OFFLINE"] = "1"
        m = AutoModel.from_pretrained(repo, local_files_only=True).eval().to(dev)
        p = AutoProcessor.from_pretrained(repo, local_files_only=True)
        pad = "max_length" if "siglip" in key else True

        def enc_text(texts):
            t = p(text=texts, padding=pad, return_tensors="pt").to(dev)
            return m.get_text_features(**t)

        def enc_img(img):
            x = p(images=img, return_tensors="pt")["pixel_values"].to(dev)
            return m.get_image_features(pixel_values=x)
        scale = m.logit_scale.exp().item() if hasattr(m, "logit_scale") else 100.0
        bias = m.logit_bias.item() if hasattr(m, "logit_bias") else 0.0
        return enc_text, enc_img, scale, bias
    os.environ["HF_HUB_OFFLINE"] = "1"  # tokenizer files are in the local dir
    import open_clip
    # local-dir: applies the repo's open_clip_config.json preprocessing (PE-Core: squash
    # resize, bilinear, mean/std 0.5), which a bare checkpoint path would not.
    name = {"pecore-s16": f"local-dir:{HERE}/dl/pecore", "siglip2-b16": f"local-dir:{HERE}/dl/siglip2"}[key]
    m, _, prep = open_clip.create_model_and_transforms(name)
    m = m.eval().to(dev)
    tok = open_clip.get_tokenizer(name)
    enc_text = lambda texts: m.encode_text(tok(texts).to(dev))
    enc_img = lambda img: m.encode_image(prep(img).unsqueeze(0).to(dev))
    scale = m.logit_scale.exp().item()
    bias = m.logit_bias.item() if getattr(m, "logit_bias", None) is not None else 0.0
    return enc_text, enc_img, scale, bias


def norm(x):
    if not torch.is_tensor(x):  # newer transformers return a ModelOutput
        x = x.pooler_output
    x = x.float()
    return x / x.norm(dim=-1, keepdim=True)


for key in sys.argv[1:]:
    enc_text, enc_img, scale, bias = load(key)
    with torch.no_grad():
        T = []
        for n in names:
            texts = [t.format(s) for s in CLASSES[n][1] for t in TEMPLATES]
            e = norm(enc_text(texts)).mean(0)
            T.append(e / e.norm())
        T = torch.stack(T)
        E, L, ms = [], [], []
        for i, pth in enumerate(paths):
            img = Image.open(f"{BENCH}/{pth}").convert("RGB")
            t0 = time.time()
            f = norm(enc_img(img))
            if dev == "mps":
                torch.mps.synchronize()
            ms.append((time.time() - t0) * 1000)
            E.append(f[0].cpu().numpy())
            L.append((scale * f @ T.T + bias)[0].cpu().numpy())
            if i % 300 == 0:
                print(key, i, flush=True)
    np.savez(f"{HERE}/zs_{key}.npz", paths=np.array(paths), classes=np.array(names),
             labels=np.array([CLASSES[n][0] for n in names]), logits=np.stack(L), emb=np.stack(E),
             ms=np.array(ms), device=dev)
    print("done", key, "median ms", np.median(ms))

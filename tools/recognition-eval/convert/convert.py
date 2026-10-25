"""PE-Core-S/16-384 image tower -> Core ML (fp16 + 8-bit palettized), plus fidelity check.

Usage: python -I convert.py <out dir>
Input: 384x384 RGB image (squash-resized by the caller / Vision .scaleFill); the
normalization (x/127.5 - 1, i.e. mean = std = 0.5) is baked into the image input.
Output: `embedding` [1, 512], L2-normalized.
"""
import json, os, sys
import numpy as np, torch
from PIL import Image

EV = "/tmp/claude-501/ev" "al"
BENCH = "/tmp/claude-501/bench"
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
os.environ["HF_HUB_OFFLINE"] = "1"
import open_clip
import coremltools as ct
import coremltools.optimize as cto

name = f"local-dir:{EV}/dl/pecore"
model, _, prep = open_clip.create_model_and_transforms(name)
model = model.eval()


class Tower(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.v = m.visual

    def forward(self, x):  # x already normalized to [-1, 1]
        f = self.v(x)
        return f / f.norm(dim=-1, keepdim=True)


tower = Tower(model).eval()
ex = torch.rand(1, 3, 384, 384) * 2 - 1
with torch.no_grad():
    traced = torch.jit.trace(tower, ex)

mlm = ct.convert(
    traced,
    inputs=[ct.ImageType(name="image", shape=(1, 3, 384, 384), scale=1 / 127.5, bias=[-1, -1, -1],
                         color_layout=ct.colorlayout.RGB)],
    outputs=[ct.TensorType(name="embedding")],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS17,
    convert_to="mlprogram",
)
mlm.author = "Meta FAIR (PE-Core-S/16-384, Apache-2.0); converted for Moove"
mlm.license = "Apache-2.0"
mlm.short_description = "PE-Core-S/16-384 image encoder: 384x384 RGB -> L2-normalized 512-d embedding"
mlm.save(f"{OUT}/fp16.mlpackage")
print("saved fp16")

cfg = cto.coreml.OptimizationConfig(global_config=cto.coreml.OpPalettizerConfig(mode="kmeans", nbits=8, granularity="per_tensor"))
pal = cto.coreml.palettize_weights(mlm, cfg)
pal.save(f"{OUT}/pal8.mlpackage")
print("saved pal8")

# Fidelity on 50 bench crops (25 public, 25 iPad), same squash resize as open_clip.
rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
rng = np.random.default_rng(1)
pub = [r for r in rows if r["split"] == "public"]
ipd = [r for r in rows if r["split"] == "ipad"]
pick = [pub[i] for i in rng.choice(len(pub), 25, replace=False)] + [ipd[i] for i in rng.choice(len(ipd), 25, replace=False)]
res = {"fp16": [], "pal8": []}
for r in pick:
    img = Image.open(f"{BENCH}/{r['path']}").convert("RGB")
    with torch.no_grad():
        ref = tower(prep(img).unsqueeze(0))[0].numpy()
    sq = img.resize((384, 384), Image.BILINEAR)
    for k, m in (("fp16", mlm), ("pal8", pal)):
        e = m.predict({"image": sq})["embedding"].reshape(-1)
        res[k].append(float(np.dot(ref, e) / np.linalg.norm(e)))
for k, v in res.items():
    print(k, "cosine mean %.5f min %.5f" % (np.mean(v), np.min(v)))
json.dump(res, open(f"{OUT}/fidelity.json", "w"))

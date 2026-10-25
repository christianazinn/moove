"""Build multi-view crops for every manifest object in scans that have saved frames, embed them
with PE-Core-S/16-384 (same open_clip local-dir pipeline as ../zs_eval.py), cache to mv_emb.npz.
Also re-embeds the auto photos (bench/ipad/...) for the single-photo baseline."""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from mv_common import *
import torch

PADS = (1.0, 1.3, 1.6)
rows = [json.loads(l) for l in open(f"{BENCH}/ipad_manifest.jsonl")]
scans = sorted(s for s in os.listdir(FRAMES) if os.path.exists(f"{FRAMES}/{s}/frames/cameras.json"))
rows = [r for r in rows if r["scan"] in scans]
print(len(rows), "objects in", len(scans), "scans with frames")

os.environ["HF_HUB_OFFLINE"] = "1"
import open_clip
name = f"local-dir:/tmp/claude-501/eval/dl/pecore"
m, _, prep = open_clip.create_model_and_transforms(name)
dev = "mps" if torch.backends.mps.is_available() else "cpu"
m = m.eval().to(dev)


@torch.no_grad()
def embed(imgs):
    out = []
    for i in range(0, len(imgs), 32):
        x = torch.stack([prep(im) for im in imgs[i:i + 32]]).to(dev)
        e = m.encode_image(x).float(); out.append((e / e.norm(dim=-1, keepdim=True)).cpu().numpy())
    return np.concatenate(out) if out else np.zeros((0, 512), np.float32)


auto = embed([Image.open(f"{BENCH}/{r['path']}").convert("RGB") for r in rows])
recs, imgs = [], []
os.makedirs(f"{HERE}/crops", exist_ok=True)
for scan in scans:
    g, cams, boxes = load_scan(scan)
    frames = [Image.open(f"{FRAMES}/{scan}/frames/{i:02d}.jpg").convert("RGB") for i in range(len(cams))]
    sharp = [lap_var(f.crop((160, 120, 480, 360))) for f in frames]  # frame-center sharpness, like the app
    typical = float(np.median(sharp))
    objs = {o["id"]: o for o in g["objects"]}
    for ri, r in enumerate(rows):
        if r["scan"] != scan: continue
        o = objs.get(r["object_id"])
        if o is None: print("missing object", r["object_id"]); continue
        for fi, cam in enumerate(cams):
            c = candidate(o, cam, boxes)
            if c is None: continue
            s = score(c, sharp[fi], typical)
            # keep a relaxed pool too (filtered later): partly clipped / partly occluded / small views
            if c["visible"] < 0.4 or c["occluded"] > 0.7 or c["area"] < 0.003 or c["distance"] < 0.3: continue
            for pad in PADS:
                im = crop(frames[fi], c, pad)
                recs.append(dict(row=ri, frame=fi, pad=pad, score=s, area=c["area"], vis=c["visible"],
                                 occ=c["occluded"], sharp=sharp[fi] / typical, px=min(im.size)))
                imgs.append(im)
                if pad == 1.3: im.save(f"{HERE}/crops/{r['object_id'][:8]}_{fi:02d}.jpg")
E = embed(imgs)
np.savez(f"{HERE}/mv_emb.npz", auto=auto, crops=E, recs=json.dumps(recs), rows=json.dumps(rows))
print("crops", len(recs))

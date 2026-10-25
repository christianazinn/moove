"""Draw projected 3D boxes on keyframes to check the projection conventions.
usage: validate_proj.py <scan> <object-id-prefix> [<object-id-prefix> ...]  -> research3/viz/*.jpg"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mv_common import *
from PIL import ImageDraw

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "viz"); os.makedirs(out, exist_ok=True)
scan = sys.argv[1]
g, cams, boxes = load_scan(scan)
EDGES = [(a, b) for a in range(8) for b in range(a + 1, 8) if bin(a ^ b).count("1") == 1]
for pre in sys.argv[2:]:
    obj = next(o for o in g["objects"] if o["id"].startswith(pre))
    cands = []
    for i, cam in enumerate(cams):
        c = candidate(obj, cam, boxes)
        if c and c["visible"] > 0.5: cands.append((c["area"] * (1 - c["occluded"]), i, c))
    cands.sort(reverse=True)
    for _, i, c in cands[:3]:
        img = Image.open(f"{FRAMES}/{scan}/frames/{i:02d}.jpg").convert("RGB")
        d = ImageDraw.Draw(img)
        u, v, _ = cams[i].project(corners(obj))
        for a, b in EDGES: d.line([(u[a], v[a]), (u[b], v[b])], fill=(255, 0, 0), width=2)
        img.transpose(Image.ROTATE_270).save(f"{out}/{scan}_{pre}_{i:02d}_occ{c['occluded']:.2f}.jpg")
        print(pre, obj.get("category"), i, {k: round(v, 2) if isinstance(v, float) else v for k, v in c.items() if k != "full"})

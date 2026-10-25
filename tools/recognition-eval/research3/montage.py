"""Contact sheet: auto photo + saved pad-1.3 crops for given object-id prefixes -> viz/sheet_<name>.jpg"""
import sys, os, json, glob
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(l) for l in open("/tmp/claude-501/bench/ipad_manifest.jsonl")]
S = 160; lines = []
for pre in sys.argv[2:]:
    r = next(r for r in rows if r["object_id"].startswith(pre))
    ims = [Image.open(f"/tmp/claude-501/bench/{r['path']}")] + [Image.open(p) for p in sorted(glob.glob(f"{HERE}/crops/{pre}_*.jpg"))]
    lines.append([im.convert("RGB").resize((S, S)) for im in ims[:8]])
sheet = Image.new("RGB", (S * 8, S * len(lines)), "white")
for y, l in enumerate(lines):
    for x, im in enumerate(l): sheet.paste(im, (x * S, y * S))
sheet.save(f"{HERE}/viz/sheet_{sys.argv[1]}.jpg")

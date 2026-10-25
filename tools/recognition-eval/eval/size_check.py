"""Detector / kNN public accuracy by crop size (min side), to see if small crops hurt the detector."""
import json, numpy as np
from PIL import Image
rows = [json.loads(l) for l in open("/tmp/claude-501/bench/manifest.jsonl")]
P = json.load(open("/tmp/claude-501/eval/predictions.json"))
idx = [i for i, r in enumerate(rows) if r["split"] == "public"]
ms = np.array([min(Image.open("/tmp/claude-501/bench/" + rows[i]["path"]).size) for i in idx])
canon = lambda x: {"ceiling fan": "fan"}.get(x, x)
print("min-side quartiles", np.percentile(ms, [25, 50, 75]))
for m in ["Detector (app thresholds)", "Detector (app thr., largest-box pick)", [k for k in P if k.startswith("VNClassify")][0], "FeaturePrint kNN k=5"]:
    ok = np.array([canon(P[m][i]) == canon(rows[i]["label"]) for i in idx])
    none = np.array([P[m][i] == "none" for i in idx])
    print(f"{m:40s}", " ".join(f"[{lo},{hi}): acc {100*ok[(ms>=lo)&(ms<hi)].mean():.0f}% none {100*none[(ms>=lo)&(ms<hi)].mean():.0f}% n={((ms>=lo)&(ms<hi)).sum()}" for lo, hi in [(0,150),(150,300),(300,600),(600,9999)]))

# "fair to the detector" subset: classes the detector vocabulary has, crops >= 150 px min side
import re
src = open("/Users/rioschillmoeller/moove/ios/MooveKit/Sources/MooveKit/Room/ObjectVocabulary.swift").read()
blk = src.split("categories: [String: String] = [")[1].split("\n    ]")[0]
cats = set(dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', blk)).values())
sub = np.array([rows[i]["label"] in cats for i in idx]) & (ms >= 150)
print(f"\nSubset: in-vocabulary classes and min side >= 150 px (n={sub.sum()})")
print("| Method | top-1 % on subset |\n|---|---|")
for m in P:
    if m == "paths":
        continue
    ok = np.array([canon(P[m][i]) == canon(rows[i]["label"]) for i in idx])
    print(f"| {m} | {100*ok[sub].mean():.1f} |")

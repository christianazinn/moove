import json, re, collections
import numpy as np
BENCH = "/tmp/claude-501/bench"; EVAL = "/tmp/claude-501/eval"
VOCAB = "/Users/rioschillmoeller/moove/ios/MooveKit/Sources/MooveKit/Room/ObjectVocabulary.swift"
src = open(VOCAB).read()
blk = src.split("categories: [String: String] = [")[1].split("\n    ]")[0]
CAT = dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', blk))
blk = src.split("minimumConfidence: [String: Float] = [")[1].split("\n    ]")[0]
MINC = {k: float(v) for k, v in re.findall(r'"([^"]+)":\s*([0-9.]+)', blk)}
DEFC = float(re.search(r"defaultMinimumConfidence: Float = ([0-9.]+)", src).group(1))
rows = [json.loads(l) for l in open(f"{BENCH}/manifest.jsonl")]
raw = {r["path"]: r for r in (json.loads(l) for l in open(f"{EVAL}/vision_raw.jsonl"))}
FIXTURE = {"radiator", "shower curtain", "towel rack"}
CANON = {"ceiling fan": "fan"}
def truth(r):
    t = CANON.get(r["label"], r["label"])
    return "none" if t in FIXTURE else t
def pred(dets, cat=CAT, minc=MINC, defc=DEFC, drop=frozenset()):
    """App-like single-image pick: highest-score detection whose category passes its threshold.
    Categories in `drop` (reject/fixture) are not objects."""
    best, bs = "none", -1
    for lab, s, box in dets:
        c = cat.get(lab)
        if c is None or c in drop: continue
        if s >= minc.get(c, defc) and s > bs: best, bs = c, s
    return best, bs

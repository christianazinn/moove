"""Rule-based per-label thresholds: highest t (0.05 grid, never below current) keeping >= 90% of correct firings
(public + iPad photos + keyframe sightings pooled; firing = the label's best box with area >= 0.05 in a crop),
reported with wrong firings removed. Labels with < 5 correct firings are left to the manual list."""
import sys, json; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from proposal import *
P = cfg_map()
F = collections.defaultdict(lambda: {"ok": [], "bad": []})
for r in rows:
    t = tgt(truth(r)) if r["label"] != "unclear" else None
    if t is None: continue
    best = {}
    for lab, s, b in raw[r["path"]]["det"]:
        if b[2]*b[3] >= 0.05: best[lab] = max(best.get(lab, 0), s)
    for lab, s in best.items():
        c = P.cat.get(lab)
        if c and c != IGN: F[lab]["ok" if c == t else "bad"].append(s)
for a in (json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_assoc.jsonl")):
    if "obj" not in a or a["truth"] == "unclear": continue
    c = P.cat.get(a["label"])
    if c and c != IGN: F[a["label"]]["ok" if c == tgt("none" if a["truth"] in FIXTURE else a["truth"]) else "bad"].append(a["score"])
out = {}
print("| label | category | n right / wrong | current thr | right kept / wrong kept @current | proposed thr | right kept / wrong kept @proposed |")
print("|---|---|---|---|---|---|---|")
for lab, d in sorted(F.items(), key=lambda kv: -len(kv[1]["ok"])):
    ok, bad = np.array(d["ok"]), np.array(d["bad"]); c = P.cat[lab]; cur = P.thr(lab, c)
    if len(ok) < 5: continue
    kc, bc = (ok >= cur).sum(), (bad >= cur).sum(); best = cur
    for t in np.arange(cur, 0.951, 0.05):
        if (ok >= t).sum() >= 0.9 * kc: best = round(float(t), 2)
    out[lab] = best
    print(f"| {lab} | {c} | {len(ok)} / {len(bad)} | {cur:.2f} | {kc} / {bc} | {best:.2f} | {(ok>=best).sum()} / {(bad>=best).sum()} |")
json.dump(out, open("/tmp/claude-501/eval/research5/rule_lminc.json", "w"), indent=1)

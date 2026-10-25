"""Associates full-frame detections (frames_det.jsonl) with scanned objects (geometry.json boxes
projected into each keyframe) whose truth is in the bench manifest. Writes frames_assoc.jsonl."""
import sys, json, os, collections
sys.path.insert(0, "/tmp/claude-501/eval/research3"); sys.path.insert(0, "/tmp/claude-501/eval/research5")
from mv_common import load_scan, candidate, FRAMES
from common import rows
truth = {}
for r in rows:
    if r["split"] == "ipad": truth[(r["scan"], r["object_id"])] = r
fd = [json.loads(l) for l in open("/tmp/claude-501/eval/research5/frames_det.jsonl")]
by_scan = collections.defaultdict(dict)
for d in fd:
    p = d["path"]; scan = p.split("/ipad_frames/")[1].split("/")[0]; i = int(os.path.basename(p)[:-4])
    by_scan[scan][i] = d["det"]
def iou(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1]); x1, y1 = min(a[0]+a[2], b[0]+b[2]), min(a[1]+a[3], b[1]+b[3])
    i = max(x1-x0, 0)*max(y1-y0, 0); u = a[2]*a[3]+b[2]*b[3]-i
    return i/u if u > 0 else 0, (i/(a[2]*a[3]) if a[2]*a[3] > 0 else 0)
out = open("/tmp/claude-501/eval/research5/frames_assoc.jsonl", "w")
stats = collections.Counter()
for scan, frames in sorted(by_scan.items()):
    g, cams, boxes = load_scan(scan)
    objs = [o for o in g["objects"] if (scan, o["id"]) in truth]
    stats["objs_total"] += len(g["objects"]); stats["objs_truth"] += len(objs)
    for i, dets in sorted(frames.items()):
        cam = cams[i]
        cands = []
        for o in objs:
            c = candidate(o, cam, boxes)
            if c and c["occluded"] < 0.6: cands.append((o, c))
        for lab, s, (bx, by, bw, bh) in dets:
            sr = (1-by-bh, 1-bx-bw, bh, bw)  # sensor-normalized, top-left origin
            best = None
            for o, c in cands:
                v, inside = iou(sr, c["rect"])
                if v >= 0.25 and inside >= 0.5 and (best is None or v > best[1]): best = (o, v)
            rec = dict(scan=scan, frame=i, label=lab, score=s, area=bw*bh)
            if best:
                t = truth[(scan, best[0]["id"])]
                rec.update(obj=best[0]["id"], iou=round(best[1], 3), truth=t["label"], true_object=t["true_object"], recorded=t["detector_label"])
                stats["matched"] += 1
            else: stats["unmatched"] += 1
            out.write(json.dumps(rec) + "\n")
print(dict(stats))

"""Leave-one-ROOM-out: several scans re-scan the same room (same cabinets, beds, garage boxes), so
leave-one-scan-out leaks the same physical object into training. Rooms grouped by shared objects."""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research2")
import fewshot, fewshot2
from fewshot2 import *
ROOM = {"2026-10-24T03-57-34": "A sink room", "2026-10-24T07-07-37": "A sink room", "2026-10-24T07-05-11": "B desk",
        "2026-10-24T08-53-59": "C bunk room", "2026-10-24T17-56-45": "C bunk room",
        "2026-10-24T19-43-54": "D dorm+bath", "2026-10-24T21-35-31": "D dorm+bath", "2026-10-24T17-39-03": "E bedroom",
        "2026-10-25T02-01-29": "F garage", "2026-10-25T02-05-43": "F garage"}
room = np.array([ROOM.get(s, "") for s in scan], dtype=object)
fewshot2.scan = room
names, labels, W0, Cd = text_set("V4")
y = row_class(names, labels, W0); C = len(labels); ip = np.where(is_ipad)[0]
print("rooms:", collections.Counter(room[ip]))
print("| Method (leave-one-room-out, 6 rooms) | public shots | iPad top-1 % | none P % | none R % | M1 merged % | M3 merged % |\n|---|---|---|---|---|---|---|")
for meth, hp in (("ZS", None), ("PROBE", 1.0), ("PROBE", 0.1), ("PROBE", 0.01), ("PROTO", 0.6), ("TIP", (1, 10))):
    for k in ((None,) if meth == "ZS" else (0, 1, 4, None)):
        L = fewshot2.loso_logits(meth, hp, W0, y, C, k, np.random.default_rng(7))
        p = np.empty(N, dtype=object); p[:] = "x"; p[ip] = labels[L[ip].argmax(1)]
        m = metrics(p); m1 = merged_metrics(p, MERGES["M1 bag+backpack"]); m3 = merged_metrics(p, MERGES["M3 M2 + shelf->storage"])
        print(f"| {meth} {hp if hp is not None else ''} | {'all' if k is None else k} | {f(m['ipad'])} | {f(m['nP'])} | {f(m['nR'])} | {f(m1['ipad'])} | {f(m3['ipad'])} |")

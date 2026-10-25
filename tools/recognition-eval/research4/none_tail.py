"""p(none) tail on all iPad real objects (any origin) and on iPad none rows: false-reject estimate for policy b."""
import sys
sys.path.insert(0, "/tmp/claude-501/eval/research4")
import numpy as np
import r4_common as C
C.origin = C.origin2
R = C.rows()
real = [r for r in R if r["t"] not in ("none", "unclear")]; non = [r for r in R if r["t"] == "none"]
for t in (0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9):
    fr = [r for r in real if r["p"][C.UI["none"]] >= t]
    print(f"t={t}: real rejected {len(fr)}/{len(real)} {[ (r['origin'][:2], r['rec'], r['t'], round(float(r['p'][C.UI['none']]),2)) for r in fr]} | none caught {sum(r['p'][C.UI['none']] >= t for r in non)}/{len(non)}")

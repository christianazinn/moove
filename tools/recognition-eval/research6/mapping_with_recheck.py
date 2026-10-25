import sys; sys.argv = ["fuse.py", "/Users/rioschillmoeller/moove/ios/MooveKit/Sources/MooveKit/Room/ObjectVocabulary.swift"]
sys.path.insert(0, "/tmp/claude-501/-Users-rioschillmoeller/8507c509-f62d-4008-95b2-3422d3e75c57/scratchpad/cls")
import numpy as np
import fuse as F
EN = "CoreML pal8 (Vision)"
REJ, MAR, OOV = 0.6, 0.2, 0.5
DROPCAT = {"workbench","crib","humidifier","room divider","sewing machine","air purifier","heater",
           "water dispenser","amplifier","plant stand","keyboard instrument"}
REMAPCAT = {"bin": "box"}
DROPLAB = {"workbench","crib","humidifier","room divider","sewing machine","air purifier","space heater",
           "vacuum cleaner","water dispenser","guitar amplifier","plant stand","electronic keyboard"}
REMAPLAB = {"storage bin":"box","dollhouse":"box","desktop computer":"monitor"}
LMINC = {"chair":0.6,"television":0.5,"refrigerator":0.6,"mini fridge":0.75,"desk lamp":0.55,"suitcase":0.55,
 "rug":0.7,"yoga mat":0.5,"dollhouse":0.5,"upright vacuum cleaner":0.75,"cordless stick vacuum":0.65,"robot vacuum":0.35,
 "stool":0.6,"bench":0.6,"vase":0.6,"toolbox":0.6,"pet crate":0.6,"bean bag":0.55,"laundry basket":0.55,"basket":0.6,
 "record player":0.6,"piano":0.55,"punching bag":0.6,"stuffed animal":0.6,"clothes rack":0.55,"shoe rack":0.6,
 "golf bag":0.6,"rocking horse":0.6,"game console":0.6,"printer":0.6,"dog bed":0.55,"blender":0.6}
orig_rec = F.rec.copy(); orig_pub = F.pub_det.copy()
def pub_det(cat, lminc):
    out = []
    for i, p in enumerate(F.paths):
        if not F.is_pub[i]: out.append(None); continue
        best, bs = "none", -1
        for lab, s, box in F.raw[p]:
            c = cat.get(lab)
            if c is None: continue
            thr = lminc.get(lab, F.MINC.get(c, F.DEFC)) if lminc else F.MINC.get(c, F.DEFC)
            if s >= thr and s > bs: best, bs = c, s
        out.append(best)
    return np.array(out, dtype=object)
def scen(name, ipad_drop, ipad_remap, cat_drop, cat_remap, lminc, vac_drop=False):
    rec = orig_rec.copy()
    for i in range(F.N):
        if F.is_ipad[i] and F.is_det[i]:
            r = rec[i]
            if r in ipad_drop or (vac_drop and r == "vacuum"): rec[i] = "DROPPED"
            elif r in ipad_remap: rec[i] = ipad_remap[r]
    F.rec = rec
    cat = dict(F.CAT); cat.update(cat_remap)
    for l in cat_drop: cat.pop(l, None)
    F.pub_det = pub_det(cat, lminc)
    out, act = F.run(EN, REJ, MAR, OOV, "loose+sure")
    for i in range(F.N):
        if rec[i] == "DROPPED": out[i] = "none"
    a = F.acc_m(out, F.ipad_obj); p, r = F.none_pr(out)
    lost = sum(1 for i in range(F.N) if F.ipad_obj[i] and rec[i] == "DROPPED")
    s, n = F.public_score(out)
    print(f"| {name} | {100*a:.1f} | {100*p:.1f} / {100*r:.1f} | {lost} | {100*s:.1f} (n={n}) |")
    return out
print("| Scenario (with #381 recheck) | iPad real top-1 % (83) | none P / R % (30) | real objects dropped | public, detector fired % |")
print("|---|---|---|---|---|")
base = scen("shipped (main)", set(), {}, set(), {}, None)
scen("+ remaps only (bin/dollhouse→box, desktop→monitor)", set(), REMAPCAT, set(), REMAPLAB, None)
scen("+ remaps + drops (generic vacuum kept)", DROPCAT, REMAPCAT, DROPLAB - {"vacuum cleaner"}, REMAPLAB, None)
scen("+ remaps + drops incl. generic vacuum (worst case: every recorded vacuum was generic)", DROPCAT, REMAPCAT, DROPLAB, REMAPLAB, None, vac_drop=True)
scen("+ remaps + drops (vacuum kept) + label floors", DROPCAT, REMAPCAT, DROPLAB - {"vacuum cleaner"}, REMAPLAB, LMINC)
scen("+ remaps + label floors (no drops)", set(), REMAPCAT, set(), REMAPLAB, LMINC)

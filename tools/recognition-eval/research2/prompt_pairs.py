"""Targeted prompt tries for the confusable pairs; per-class public accuracy (fine classes) + iPad."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research2")
from prompts import *
fine = np.array([r.get("fine_label", r["label"]) for r in rows], dtype=object)
KEYC = ["bag", "backpack", "suitcase", "table", "desk", "storage", "shelf", "chair", "television", "monitor", "laptop"]
def per(pred):
    o = []
    for c in KEYC:
        m = is_pub & (gt == c) if c != "desk" else is_pub & (fine == "desk")
        if c == "table": m = is_pub & (fine == "table")
        o.append(f"{100*acc(pred, m):.0f}")
    return " | ".join(o)
print("| variant | pub | iPad | nP | nR | " + " | ".join(KEYC) + " |")
print("|---" * (6 + len(KEYC)) + "|")
def show(name, C, T=BASE_T):
    p, *_ = run(C, T)
    print(f"| {name} | {fmt(metrics(p))} | {per(p)} |")
show("V0", build())
def mod(**kw):
    C = build()
    for k, v in kw.items():
        C[k] = (C[k][0] if k in C else v[0], v[1] if isinstance(v, tuple) else v)
    return C
show("bag=duffel only", mod(bag=["duffel bag"]))
show("bag=duffel,gym,sports bag", mod(bag=["duffel bag", "gym bag", "sports bag"]))
show("backpack w/ straps", mod(backpack=["backpack with shoulder straps"]))
show("bag duffel + backpack straps", mod(bag=["duffel bag", "gym bag"], backpack=["backpack with shoulder straps", "rucksack"]))
show("table: wooden/dining/coffee", mod(table=["wooden table", "dining table", "coffee table"]))
show("table: 'table with four legs'", mod(table=["table", "table with four legs", "dining table"]))
show("desk: office/computer desk", mod(desk=["desk", "office desk", "computer desk"]))
show("bookshelf w books", mod(bookshelf=["bookshelf with books", "bookcase"]))
show("shelf: floating/unit", mod(shelf=["wall shelf", "floating shelf", "shelving unit"]))
show("shelf: + 'shelf with items'", mod(shelf=["wall shelf", "shelf", "shelf with items on it"]))
show("monitor: on desk", mod(monitor=["computer monitor", "computer monitor on a desk"]))
show("tv: flat-screen/stand", mod(television=["television", "tv", "flat screen tv on a tv stand"]))
show("chair: +dining/wooden", mod(chair=["chair", "armchair", "folding chair", "dining chair", "wooden chair"]))
# CuPL-style descriptive sentences (verbatim)
show("CuPL bag/backpack", mod(bag=["!a photo of a duffel bag, a soft cylindrical bag with handles.", "duffel bag"],
     backpack=["!a photo of a backpack, worn on the back with two shoulder straps.", "backpack"]))
show("CuPL table/storage", mod(table=["!a photo of a table, a flat top supported by legs.", "table"],
     cabinet=["!a photo of a cabinet with doors.", "cabinet"], dresser=["!a photo of a dresser with drawers.", "dresser", "chest of drawers"]))
print()
TGT = dict(bag=["duffel bag"], table=["table", "wooden table", "dining table", "coffee table"],
           shelf=["wall shelf", "floating shelf", "shelving unit"], monitor=["computer monitor", "computer monitor on a desk"])
show("V4 targeted (bag,table,shelf,monitor)", mod(**TGT))
for nm, negs in (("+brief neg", [NEG_BRIEF]), ("+brief+generic neg", [NEG_BRIEF, NEG_GENERIC]),
                 ("+brief+generic+iPad neg", [NEG_BRIEF, NEG_GENERIC, NEG_IPAD])):
    C = mod(**TGT)
    for d in negs:
        for k, v in d.items(): C[k] = ("none", v)
    show("V4 " + nm, C)
    show("V4 " + nm + ", 8 templates", C, T_MORE)

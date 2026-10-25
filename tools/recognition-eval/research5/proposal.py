"""Proposed vocabulary: mapping fixes, ignored (dropped) labels, fixture-proxy veto labels, label thresholds."""
import sys; sys.path.insert(0, "/tmp/claude-501/eval/research5")
from sim import *
REMAP = {
    "storage bin": "box",          # fires on cardboard boxes (31 keyframes, 7/7 recorded 'bin' were boxes)
    "dollhouse": "box",            # fires on boxes / boxy storage, never a toy here
    "desktop computer": "monitor", # public: monitor 9, laptop 5 of 15
    "motorcycle": "scooter",       # public: scooter 10, bicycle 4 of 15; indoor motorcycles are rare
}
# labels that are (almost) never the thing in homes on this bench -> ignored
DROP = {"workbench", "crib", "humidifier", "room divider", "sewing machine", "air purifier", "space heater",
        "vacuum cleaner", "water dispenser", "guitar amplifier", "plant stand", "electronic keyboard"}
VETO = set()  # filled in by variants
def cfg_map(name="mapping only", drop=DROP, remap=REMAP, veto=VETO, lminc=None, minc=None):
    cat = dict(CAT); cat.update(remap)
    for l in drop: cat[l] = IGN
    return Cfg(name, cat=cat, veto=veto, lminc=lminc, minc=minc)

# Label-level minimum scores (override the category threshold). Evidence: thr_rule.py / untestable.py.
LMINC = {
    # bench-supported (public + iPad + keyframes)
    "chair": 0.6, "television": 0.5, "refrigerator": 0.6, "mini fridge": 0.75, "desk lamp": 0.55, "suitcase": 0.55,
    "rug": 0.7, "motorcycle": 0.65, "yoga mat": 0.5, "dollhouse": 0.5,
    "upright vacuum cleaner": 0.75, "cordless stick vacuum": 0.65, "robot vacuum": 0.35,
    # categories absent from the bench, misfiring on other things -> 0.55-0.6
    "stool": 0.6, "bench": 0.6, "vase": 0.6, "toolbox": 0.6, "pet crate": 0.6, "bean bag": 0.55,
    "laundry basket": 0.55, "basket": 0.6, "record player": 0.6, "piano": 0.55, "punching bag": 0.6,
    "stuffed animal": 0.6, "clothes rack": 0.55, "shoe rack": 0.6, "golf bag": 0.6,
    "rocking horse": 0.6, "game console": 0.6, "printer": 0.6, "dog bed": 0.55, "blender": 0.6,
}
def cfg_full(name="mapping + thresholds"): return cfg_map(name, lminc=LMINC)

import sys; sys.path.insert(0, '/tmp/claude-501/eval/research2')
from common import *
src = open(f"{EVAL}/zs_eval.py").read()
ns = {}
exec(src[src.index("CLASSES = {"):src.index("names = list(CLASSES)")], ns)
names, labels, W = class_weights(ns["CLASSES"], ns["TEMPLATES"])
pred, lg = predict(W, labels)
print(HDR); print("| baseline (recomputed, CPU text) |", fmt(metrics(pred)), "|")
pred0 = Z["labels"][Z["logits"].argmax(1)].astype(object)
print("| baseline (saved logits) |", fmt(metrics(pred0)), "|")
print("agree", (pred == pred0).mean(), "scale", SCALE)

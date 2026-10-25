#!/usr/bin/env python3
"""Local AI-text detector for the fraud agent (agents/src/integrations/aitext.ts).

Wire format (what PANGRAM_URL expects): POST / with {"text": "..."} -> {"score": 0.0..1.0},
higher = more likely AI-generated. GET /healthz -> {"ok": true}. Binds to 127.0.0.1 only.

Backends (pick with --backend):
  hf     a Hugging Face sequence-classification checkpoint dir (transformers + torch)
  onnx   an exported ONNX classifier + its tokenizer.json (onnxruntime + tokenizers)
  gguf   a llama.cpp classifier GGUF (llama-cpp-python, pooling_type=RANK / classification head)
  otd    a token-level detector export (per-token probabilities, windows, calibrated verdict); --model is its dir
  fixed  no model; returns --fixed-score (for wiring tests)

Examples:
  .venv/bin/python -I agents/scripts/aitext-server.py --backend otd --model ~/misc/moove-models/rc11t-c1
  python3 agents/scripts/aitext-server.py --backend hf --model ~/models/detector --ai-label 1
  python3 agents/scripts/aitext-server.py --backend onnx --model ~/models/detector.onnx --tokenizer ~/models/tokenizer.json
Then put PANGRAM_URL=http://127.0.0.1:8420/ in the repo-root .env.local (the workers restart).
"""
import argparse
import json
import math
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def softmax(xs):
    m = max(xs)
    e = [math.exp(x - m) for x in xs]
    s = sum(e)
    return [x / s for x in e]


def to_prob(logits, ai_label):
    """One logit -> sigmoid; two or more -> softmax[ai_label]."""
    logits = [float(x) for x in logits]
    if len(logits) == 1:
        return 1 / (1 + math.exp(-logits[0]))
    return softmax(logits)[ai_label]


def load_otd(args):
    """Token-level detector export (per-token AI probabilities, ONNX output `probs` [batch, seq]), scored the way its
    training repo does: textnorm.canon, windows of `width` tokens as [CLS] window [SEP] at stride width/2 with token
    probabilities averaged, document score = mean probability of non-space tokens, run score = best mean of 3
    consecutive sentences, verdict AI / Mixed / Human from calibration.json's joint thresholds (docrule.verdict).

    --model is the model directory: onnx/<--onnx-file>, tokenizer/tokenizer.json, calibration.json, config-*.json
    (width, normalize) and src/textnorm.py (the training repo's normaliser, imported from there, not vendored)."""
    import glob
    import os
    import re

    import numpy as np
    import onnxruntime as ort
    from tokenizers import Tokenizer

    d = args.model
    cfg = json.load(open(sorted(glob.glob(os.path.join(d, "config-*.json")))[0]))
    cal = json.load(open(os.path.join(d, "calibration.json")))
    width = int(cfg.get("width", 510))
    stride = 256 if width == 510 else width // 2
    norm = cfg.get("normalize")
    textnorm = None
    if norm:
        sys.path.insert(0, os.path.join(d, "src"))
        import textnorm  # noqa: E402  (the model's own normaliser)
        version = textnorm.version_of(norm)
    tok = Tokenizer.from_file(os.path.join(d, "tokenizer", "tokenizer.json"))
    cls, sep = tok.token_to_id("[CLS]"), tok.token_to_id("[SEP]")
    so = ort.SessionOptions()
    so.intra_op_num_threads = args.threads
    sess = ort.InferenceSession(os.path.join(d, "onnx", args.onnx_file), so, providers=["CPUExecutionProvider"])
    joint = cal.get("joint", cal["thresholds"])
    sent_cut = cal["thresholds"]["sentence"]
    lv = {"low": "0.01", "high": "0.001"}  # 1% and 0.1% false-positive levels
    doc_thr = {k: float(joint["document"][v]) for k, v in lv.items()}
    run_thr = {k: float(joint["run"][v]) for k, v in lv.items()}
    sent_re = re.compile(r"\S.*?(?:[.!?](?=\s|$)|$)", re.S)  # common.sentences

    def starts(n):
        return [0] if n <= width else sorted(set(list(range(0, n - width + 1, stride)) + [n - width]))

    def run_score(s, k=3):
        s = np.asarray(s, float)
        if len(s) <= k:
            return float(s.mean())
        c = np.cumsum(np.r_[0.0, s])
        return float(((c[k:] - c[:-k]) / k).max())

    def analyze(text):
        if textnorm is not None:
            text = textnorm.canon(text, version)[0]
        enc = tok.encode(text, add_special_tokens=False)
        ids, off = enc.ids, np.asarray(enc.offsets, dtype=np.int64).reshape(-1, 2)
        n = len(ids)
        if not n:
            return None
        acc, cnt = np.zeros(n), np.zeros(n)
        for a in starts(n):
            b = min(a + width, n)
            x = np.asarray([[cls] + ids[a:b] + [sep]], dtype=np.int64)
            p = sess.run(["probs"], {"input_ids": x, "attention_mask": np.ones_like(x)})[0][0]
            acc[a:b] += p[1 : b - a + 1]
            cnt[a:b] += 1
        prob = acc / np.maximum(cnt, 1)
        nws = np.concatenate([[0], np.cumsum([not c.isspace() for c in text])]).astype(np.int64)
        valid = nws[off[:, 1]] > nws[off[:, 0]]
        if not valid.any():
            return None
        sents = []
        for m in sent_re.finditer(text):
            if not m.group().strip():
                continue
            use = valid & (off[:, 1] > m.start()) & (off[:, 0] < m.end())
            if use.any():
                sents.append(float(prob[use].mean()))
        doc, run = float(prob[valid].mean()), run_score(sents)

        def verdict(level):
            k = sum(s > float(sent_cut[lv[level]]) for s in sents)
            mixed = run > run_thr[level] and k / len(sents) >= 0.05 and k >= 3  # docrule.mixed_gate
            return "AI" if doc > doc_thr[level] else "Mixed" if mixed else "Human"

        return doc, run, len(sents), n, verdict("high"), verdict("low")

    def to_fraud_scale(doc, v_high, v_low):
        """The fraud agent reads 0.5+ as 'may be AI' and 0.7+ as 'likely'. Map the calibrated levels onto that:
        below the 1% threshold -> [0, 0.5), between the 1% and 0.1% thresholds -> [0.5, 0.7), above 0.1% -> [0.7, 1].
        A Mixed verdict (an AI passage, not the whole text) lifts the score to its level's floor."""
        lo, hi = doc_thr["low"], doc_thr["high"]
        if doc <= lo:
            s = 0.5 * doc / lo
        elif doc <= hi:
            s = 0.5 + 0.2 * (doc - lo) / (hi - lo)
        else:
            s = 0.7 + 0.3 * (doc - hi) / (1 - hi)
        if v_high != "Human":
            s = max(s, 0.7)
        elif v_low != "Human":
            s = max(s, 0.5)
        return min(1.0, max(0.0, s))

    def score(text):
        r = analyze(text)
        if r is None:
            return {"score": 0.0, "verdict": "Human", "note": "no scorable tokens"}
        doc, run, ns, nt, vh, vl = r
        return {"score": round(to_fraud_scale(doc, vh, vl), 4), "document": round(doc, 4), "run": round(run, 4),
                "verdict": vh, "verdict_1pct": vl, "sentences": ns, "tokens": nt}

    return score


def load(args):
    if args.backend == "fixed":
        return lambda text: args.fixed_score
    if args.backend == "hf":
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer

        tok = AutoTokenizer.from_pretrained(args.tokenizer or args.model)
        model = AutoModelForSequenceClassification.from_pretrained(args.model).eval()

        def score(text):
            enc = tok(text, truncation=True, max_length=args.max_tokens, return_tensors="pt")
            with torch.no_grad():
                return to_prob(model(**enc).logits[0].tolist(), args.ai_label)

        return score
    if args.backend == "onnx":
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer

        tok = Tokenizer.from_file(args.tokenizer)
        tok.enable_truncation(args.max_tokens)
        sess = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])
        names = {i.name for i in sess.get_inputs()}

        def score(text):
            e = tok.encode(text)
            feed = {"input_ids": np.array([e.ids], dtype=np.int64)}
            if "attention_mask" in names:
                feed["attention_mask"] = np.array([e.attention_mask], dtype=np.int64)
            if "token_type_ids" in names:
                feed["token_type_ids"] = np.array([e.type_ids], dtype=np.int64)
            return to_prob(sess.run(None, feed)[0][0].tolist(), args.ai_label)

        return score
    if args.backend == "otd":
        return load_otd(args)
    if args.backend == "gguf":
        from llama_cpp import Llama

        llm = Llama(model_path=args.model, embedding=True, pooling_type=4, n_ctx=args.max_tokens, verbose=False)

        def score(text):
            out = llm.embed(text)
            logits = out[0] if out and isinstance(out[0], list) else out
            return to_prob(logits, args.ai_label)

        return score
    sys.exit(f"unknown backend {args.backend}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--backend", choices=["otd", "hf", "onnx", "gguf", "fixed"], default="hf")
    p.add_argument("--model", help="model dir (otd), checkpoint dir (hf), .onnx file or .gguf file")
    p.add_argument("--onnx-file", default="model-q4f16e.onnx", help="otd: the ONNX file under <model>/onnx/")
    p.add_argument("--threads", type=int, default=4, help="otd: CPU threads for onnxruntime")
    p.add_argument("--tokenizer", help="tokenizer dir (hf) or tokenizer.json (onnx); defaults to --model for hf")
    p.add_argument("--ai-label", type=int, default=1, help="output index meaning 'AI-generated' (2+ logits)")
    p.add_argument("--max-tokens", type=int, default=512)
    p.add_argument("--max-chars", type=int, default=8000, help="longer texts are cut before tokenizing")
    p.add_argument("--fixed-score", type=float, default=0.5)
    p.add_argument("--port", type=int, default=8420)
    p.add_argument("--token", help="require 'Authorization: Bearer <token>' (PANGRAM_TOKEN)")
    args = p.parse_args()
    if args.backend != "fixed" and not args.model:
        p.error("--model is required")
    score = load(args)

    class Handler(BaseHTTPRequestHandler):
        def _send(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self._send(200, {"ok": True}) if self.path == "/healthz" else self._send(404, {"error": "not found"})

        def do_POST(self):
            if args.token and self.headers.get("authorization") != f"Bearer {args.token}":
                return self._send(401, {"error": "unauthorized"})
            try:
                n = min(int(self.headers.get("content-length") or 0), 1_000_000)
                text = str(json.loads(self.rfile.read(n) or b"{}").get("text", ""))[: args.max_chars]
            except (ValueError, json.JSONDecodeError):
                return self._send(400, {"error": "send JSON {\"text\": \"...\"}"})
            if not text.strip():
                return self._send(400, {"error": "empty text"})
            try:
                r = score(text)
                self._send(200, r if isinstance(r, dict) else {"score": round(max(0.0, min(1.0, float(r))), 4)})
            except Exception as e:  # a model error must not kill the server; the fraud agent logs it
                self._send(500, {"error": f"model error: {e}"[:300]})

        def log_message(self, fmt, *a):
            sys.stderr.write("[aitext] " + (fmt % a) + "\n")

    print(f"[aitext] {args.backend} detector on http://127.0.0.1:{args.port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()

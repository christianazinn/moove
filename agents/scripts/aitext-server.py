#!/usr/bin/env python3
"""Local AI-text detector for the fraud agent (agents/src/integrations/aitext.ts).

Wire format (what PANGRAM_URL expects): POST / with {"text": "..."} -> {"score": 0.0..1.0},
higher = more likely AI-generated. GET /healthz -> {"ok": true}. Binds to 127.0.0.1 only.

Backends (pick with --backend):
  hf     a Hugging Face sequence-classification checkpoint dir (transformers + torch)
  onnx   an exported ONNX classifier + its tokenizer.json (onnxruntime + tokenizers)
  gguf   a llama.cpp classifier GGUF (llama-cpp-python, pooling_type=RANK / classification head)
  fixed  no model; returns --fixed-score (for wiring tests)

Examples:
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
    p.add_argument("--backend", choices=["hf", "onnx", "gguf", "fixed"], default="hf")
    p.add_argument("--model", help="checkpoint dir (hf), .onnx file or .gguf file")
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
                self._send(200, {"score": round(max(0.0, min(1.0, float(score(text)))), 4)})
            except Exception as e:  # a model error must not kill the server; the fraud agent logs it
                self._send(500, {"error": f"model error: {e}"[:300]})

        def log_message(self, fmt, *a):
            sys.stderr.write("[aitext] " + (fmt % a) + "\n")

    print(f"[aitext] {args.backend} detector on http://127.0.0.1:{args.port}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()

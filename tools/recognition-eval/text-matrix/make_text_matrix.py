#!/usr/bin/env python3
"""Build a label text-embedding matrix for an on-device CLIP-style crop classifier.

Writes, for N labels and embedding size D:
  <out>.npy   float16 (N, D), each row L2-normalized (numpy .npy)
  <out>.f16   the same matrix as raw little-endian fp16, row-major (easy to mmap from Swift)
  <out>.json  labels, phrases, templates, model id + commit, D, logit scale/bias, checksums

The image tower you ship MUST come from the same checkpoint (and resolution) as the text tower used
here, or the dot products are meaningless:
  batmac/ViT-B-16-SigLIP2-Image-CoreML        -> --model hf-hub:timm/ViT-B-16-SigLIP2 (exact source, open_clip)
                                                 or google/siglip2-base-patch16-224 (D=768; same weights,
                                                 per both model cards; check one image if unsure)
  FluidInference/siglip2-base-patch16-256-coreml -> --model google/siglip2-base-patch16-256 (D=768)
  PE-Core-S16-384 (timm / facebook)           -> --model hf-hub:timm/PE-Core-S-16-384 (D=512, open_clip)

Labels file: one label per line; blank lines and '#' comments are ignored. Optionally give
synonyms/phrasings after a TAB, separated by ';' (the label itself is used when none are given):
    e-scooter<TAB>electric scooter;electric kick scooter
    upright vacuum<TAB>upright vacuum cleaner
Each label's row is the mean of the normalized embeddings of every (phrase x template), renormalized.

Modes (SigLIP / SigLIP2 checkpoints only for --mode sparse):
  full    load the whole checkpoint with transformers (or open_clip for hf-hub: ids). ~1.5 GB download
          for siglip2-base. Use this on a machine with fast internet.
  sparse  bandwidth saver: reads the safetensors header with HTTP range requests, then fetches ONLY
          the text-tower tensors plus the token-embedding ROWS the labels actually use (the 256k x 768
          Gemma vocabulary is 787 MB of the 1.13 GB fp32 text tower). For siglip2-base that is about
          343 MB instead of 1.5 GB, resumable (chunks are cached in --cache). Numerically the same
          model: SigLIP's text tower has no attention mask and only ever looks up the ids it is given,
          so re-indexing the vocabulary to the used ids does not change the output.

Examples:
  pip install torch transformers sentencepiece protobuf numpy safetensors   # (+ open_clip_torch for PE-Core)
  python make_text_matrix.py labels.txt --out moove_labels_siglip2_b16_224
  python make_text_matrix.py labels.txt --out m --mode sparse --endpoint https://hf-mirror.com
  python make_text_matrix.py labels.txt --out m_pe --model hf-hub:timm/PE-Core-S-16-384
  python make_text_matrix.py labels.txt --out m --mode sparse --weights /path/model.safetensors --tokenizer-dir /path/dir
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import time
import urllib.request
from pathlib import Path

import numpy as np

DEFAULT_TEMPLATES = [
    "this is a photo of {}.",
    "a photo of a {}.",
    "a photo of the {} in a room.",
    "a cropped photo of a {}.",
]
SAFETENSORS_DTYPES = {"F32": np.float32, "F16": np.float16, "BF16": None}


# ----------------------------------------------------------------------------------------- labels
def read_labels(path: str) -> list[tuple[str, list[str]]]:
    out = []
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if "\t" in line:
            label, rest = line.split("\t", 1)
            phrases = [p.strip() for p in rest.split(";") if p.strip()]
        else:
            label, phrases = line, []
        label = label.strip()
        out.append((label, phrases or [label]))
    labels = [l for l, _ in out]
    dupes = {l for l in labels if labels.count(l) > 1}
    if dupes:
        sys.exit(f"duplicate labels: {sorted(dupes)}")
    if not out:
        sys.exit("no labels")
    return out


def prompts_for(phrases: list[str], templates: list[str], lowercase: bool) -> list[str]:
    ps = [t.format(p) for p in phrases for t in templates]
    return [p.lower() for p in ps] if lowercase else ps


def pool(emb: np.ndarray, counts: list[int]) -> np.ndarray:
    """emb: (sum(counts), D) raw embeddings -> (len(counts), D) mean of normalized, renormalized."""
    emb = emb / np.linalg.norm(emb, axis=1, keepdims=True)
    rows, i = [], 0
    for c in counts:
        m = emb[i : i + c].mean(axis=0)
        rows.append(m / np.linalg.norm(m))
        i += c
    return np.stack(rows).astype(np.float32)


# ------------------------------------------------------------------------------------ HTTP ranges
def hf_url(endpoint: str, repo: str, revision: str, fname: str) -> str:
    return f"{endpoint.rstrip('/')}/{repo}/resolve/{revision}/{fname}"


def http_get(url: str, start: int | None = None, end: int | None = None, retries: int = 6) -> bytes:
    """GET bytes [start, end] inclusive (whole file if start is None). Follows redirects, retries."""
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": "moove-make-text-matrix/1"})
        if start is not None:
            req.add_header("Range", f"bytes={start}-{end}")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                if start is not None and r.status != 206:
                    raise RuntimeError(f"server ignored the Range header (HTTP {r.status}) for {url}")
                data = r.read()
            if start is not None and len(data) != end - start + 1:
                raise IOError(f"short read {len(data)} != {end - start + 1}")
            return data
        except Exception as e:  # noqa: BLE001
            if attempt == retries - 1:
                raise
            wait = 2 ** attempt
            print(f"  retry in {wait}s after: {e}", file=sys.stderr)
            time.sleep(wait)
    raise AssertionError


class RangeSource:
    """Byte ranges from a remote URL (cached on disk per chunk) or a local file."""

    def __init__(self, url_or_path: str, cache: Path | None):
        self.local = os.path.exists(url_or_path)
        self.src = url_or_path
        self.cache = cache
        self.fetched = 0
        if cache:
            cache.mkdir(parents=True, exist_ok=True)

    def read(self, start: int, end_exclusive: int) -> bytes:
        if end_exclusive <= start:
            return b""
        if self.local:
            with open(self.src, "rb") as f:
                f.seek(start)
                return f.read(end_exclusive - start)
        key = None
        if self.cache:
            key = self.cache / f"{start}-{end_exclusive}.bin"
            if key.exists() and key.stat().st_size == end_exclusive - start:
                return key.read_bytes()
        t0 = time.time()
        data = http_get(self.src, start, end_exclusive - 1)
        self.fetched += len(data)
        dt = max(time.time() - t0, 1e-6)
        print(f"  fetched {len(data)/1e6:7.2f} MB at {len(data)/dt/1e3:7.1f} KB/s "
              f"(total {self.fetched/1e6:.1f} MB)", file=sys.stderr)
        if key:
            tmp = key.with_suffix(".part")
            tmp.write_bytes(data)
            tmp.rename(key)
        return data


def read_header(src: RangeSource) -> tuple[dict, int]:
    n = struct.unpack("<Q", src.read(0, 8))[0]
    header = json.loads(src.read(8, 8 + n))
    header.pop("__metadata__", None)
    return header, 8 + n


def to_array(buf: bytes, dtype: str, shape: list[int]) -> np.ndarray:
    if dtype == "BF16":
        u16 = np.frombuffer(buf, dtype="<u2").astype(np.uint32) << 16
        return u16.view(np.float32).reshape(shape)
    npdt = SAFETENSORS_DTYPES.get(dtype)
    if npdt is None:
        raise ValueError(f"unsupported dtype {dtype}")
    return np.frombuffer(buf, dtype=np.dtype(npdt).newbyteorder("<")).reshape(shape).astype(np.float32)


def fetch_tensors(src: RangeSource, header: dict, base: int, names: list[str], chunk_mb: int = 32) -> dict:
    """Fetch whole tensors, coalescing neighbours into <= chunk_mb requests."""
    spans = sorted((header[n]["data_offsets"][0], header[n]["data_offsets"][1], n) for n in names)
    out, group = {}, []
    limit = chunk_mb * 1_000_000

    def flush():
        if not group:
            return
        g0, g1 = group[0][0], group[-1][1]
        blob = src.read(base + g0, base + g1)
        for a, b, n in group:
            h = header[n]
            out[n] = to_array(blob[a - g0 : b - g0], h["dtype"], h["shape"])
        group.clear()

    for a, b, n in spans:
        if b - a > limit:  # one big tensor: fetch it in pieces
            flush()
            h = header[n]
            parts = [src.read(base + s, base + min(s + limit, b)) for s in range(a, b, limit)]
            out[n] = to_array(b"".join(parts), h["dtype"], h["shape"])
            continue
        if group and (b - group[0][0] > limit or a != group[-1][1]):
            flush()
        group.append((a, b, n))
    flush()
    return out


def fetch_rows(src: RangeSource, header: dict, base: int, name: str, ids: list[int]) -> np.ndarray:
    """Rows `ids` (sorted unique) of a 2-D tensor, coalescing consecutive ids."""
    h = header[name]
    rows_n, width = h["shape"]
    item = {"F32": 4, "F16": 2, "BF16": 2}[h["dtype"]]
    row_bytes = width * item
    a0 = h["data_offsets"][0]
    out = np.zeros((len(ids), width), np.float32)
    i = 0
    while i < len(ids):
        j = i
        while j + 1 < len(ids) and ids[j + 1] == ids[j] + 1 and j - i < 4096:
            j += 1
        blob = src.read(base + a0 + ids[i] * row_bytes, base + a0 + (ids[j] + 1) * row_bytes)
        out[i : j + 1] = to_array(blob, h["dtype"], [j - i + 1, width])
        i = j + 1
    return out


# ----------------------------------------------------------------------------- SigLIP tokenizing
def load_siglip_tokenizer(tok_dir: str):
    from transformers import AutoTokenizer

    return AutoTokenizer.from_pretrained(tok_dir)


def tokenize_siglip(tok, prompts: list[str], max_len: int) -> np.ndarray:
    # SigLIP / SigLIP2 were trained with right padding to a fixed length and no attention mask.
    enc = tok(prompts, padding="max_length", max_length=max_len, truncation=True, return_tensors="np")
    return enc["input_ids"].astype(np.int64)


def siglip_text_classes(model_type: str):
    import transformers as T

    if model_type == "siglip2":
        return T.Siglip2Config, T.Siglip2TextModel
    return T.SiglipConfig, T.SiglipTextModel


# ------------------------------------------------------------------------------------ backends
def run_full_siglip(args, prompts: list[str]):
    import torch
    from transformers import AutoConfig, AutoModel, AutoTokenizer

    src = args.local_dir or args.model
    cfg = AutoConfig.from_pretrained(src, revision=args.revision)
    tok = AutoTokenizer.from_pretrained(args.tokenizer_dir or src, revision=args.revision)
    model = AutoModel.from_pretrained(src, revision=args.revision, torch_dtype=torch.float32).eval()
    max_len = getattr(cfg.text_config, "max_position_embeddings", 64)
    ids = torch.from_numpy(tokenize_siglip(tok, prompts, max_len))
    embs = []
    with torch.no_grad():
        for i in range(0, len(ids), 64):
            out = model.text_model(input_ids=ids[i : i + 64])
            embs.append(out.pooler_output.float().numpy())
    scale = float(model.logit_scale.detach().exp()) if hasattr(model, "logit_scale") else None
    bias = float(model.logit_bias.detach()) if hasattr(model, "logit_bias") else None
    return np.concatenate(embs), scale, bias, cfg.model_type


def run_sparse_siglip(args, prompts: list[str]):
    import torch

    cache = Path(args.cache) / args.model.replace("/", "--") / args.revision
    tok_dir = Path(args.tokenizer_dir) if args.tokenizer_dir else cache / "tok"
    if not args.tokenizer_dir:
        tok_dir.mkdir(parents=True, exist_ok=True)
        # tokenizer.model (4 MB sentencepiece) instead of tokenizer.json (34 MB)
        for f in ["config.json", "tokenizer_config.json", "special_tokens_map.json", "tokenizer.model"]:
            p = tok_dir / f
            if not p.exists():
                print(f"downloading {f}", file=sys.stderr)
                p.write_bytes(http_get(hf_url(args.endpoint, args.model, args.revision, f)))
    cfg_json = json.loads((tok_dir / "config.json").read_text())
    model_type = cfg_json.get("model_type", "siglip")
    Config, TextModel = siglip_text_classes(model_type)
    cfg = Config.from_pretrained(str(tok_dir))
    tok = load_siglip_tokenizer(str(tok_dir))
    max_len = getattr(cfg.text_config, "max_position_embeddings", 64)
    ids = tokenize_siglip(tok, prompts, max_len)

    weights = args.weights or hf_url(args.endpoint, args.model, args.revision, "model.safetensors")
    src = RangeSource(weights, None if os.path.exists(weights) else cache / "chunks")
    header, base = read_header(src)
    emb_name = "text_model.embeddings.token_embedding.weight"
    names = [n for n in header if n.startswith("text_model.") and n != emb_name]
    for extra in ("logit_scale", "logit_bias"):
        if extra in header:
            names.append(extra)
    need = sum(header[n]["data_offsets"][1] - header[n]["data_offsets"][0] for n in names)
    used = sorted(set(int(x) for x in ids.ravel()))
    print(f"text tower without vocab: {need/1e6:.1f} MB; vocab rows needed: {len(used)} "
          f"of {header[emb_name]['shape'][0]}", file=sys.stderr)

    tensors = fetch_tensors(src, header, base, names)
    rows = fetch_rows(src, header, base, emb_name, used)

    remap = {old: new for new, old in enumerate(used)}
    small_ids = np.vectorize(remap.__getitem__)(ids)
    tcfg = cfg.text_config
    tcfg.vocab_size = len(used)
    model = TextModel(tcfg).eval()
    sd = {n: torch.from_numpy(np.ascontiguousarray(v)) for n, v in tensors.items() if n.startswith("text_model.")}
    sd[emb_name] = torch.from_numpy(rows)
    # transformers 4.x nests the tower under `text_model.`; 5.x's SiglipTextModel is flat.
    if not any(k.startswith("text_model.") for k in model.state_dict()):
        sd = {k[len("text_model."):]: v for k, v in sd.items()}
    missing, unexpected = model.load_state_dict(sd, strict=False)
    missing = [m for m in missing if "position_ids" not in m]
    if missing or unexpected:
        sys.exit(f"state dict mismatch: missing={missing} unexpected={unexpected}")
    embs = []
    with torch.no_grad():
        t = torch.from_numpy(small_ids)
        for i in range(0, len(t), 64):
            embs.append(model(input_ids=t[i : i + 64]).pooler_output.float().numpy())
    scale = float(np.exp(tensors["logit_scale"].ravel()[0])) if "logit_scale" in tensors else None
    bias = float(tensors["logit_bias"].ravel()[0]) if "logit_bias" in tensors else None
    print(f"downloaded {src.fetched/1e6:.1f} MB of weights this run", file=sys.stderr)
    return np.concatenate(embs), scale, bias, model_type


def run_open_clip(args, prompts: list[str]):
    import open_clip
    import torch

    model, _, _ = open_clip.create_model_and_transforms(args.model)
    tok = open_clip.get_tokenizer(args.model)
    model.eval()
    embs = []
    with torch.no_grad():
        for i in range(0, len(prompts), 64):
            embs.append(model.encode_text(tok(prompts[i : i + 64])).float().numpy())
    scale = float(model.logit_scale.exp()) if hasattr(model, "logit_scale") else None
    bias = float(model.logit_bias) if getattr(model, "logit_bias", None) is not None else None
    return np.concatenate(embs), scale, bias, "open_clip"


def repo_commit(endpoint: str, repo: str, revision: str) -> str | None:
    try:
        req = urllib.request.Request(hf_url(endpoint, repo, revision, "config.json"), method="HEAD")
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.headers.get("x-repo-commit")
    except Exception:  # noqa: BLE001
        return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("labels")
    ap.add_argument("--out", required=True, help="output prefix (writes .npy, .f16, .json)")
    ap.add_argument("--model", default="google/siglip2-base-patch16-224",
                    help="HF repo id (SigLIP/SigLIP2) or an open_clip id like hf-hub:timm/PE-Core-S-16-384")
    ap.add_argument("--revision", default="main")
    ap.add_argument("--mode", choices=["full", "sparse"], default="full")
    ap.add_argument("--endpoint", default=os.environ.get("HF_ENDPOINT", "https://huggingface.co"),
                    help="e.g. https://hf-mirror.com (sparse mode / commit lookup)")
    ap.add_argument("--templates", nargs="*", default=DEFAULT_TEMPLATES, help="'{}' is the phrase")
    ap.add_argument("--no-lowercase", action="store_true", help="SigLIP2 was trained on lowercased text")
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/moove-text-matrix"))
    ap.add_argument("--weights", help="sparse: a local model.safetensors instead of the remote one")
    ap.add_argument("--tokenizer-dir", help="dir with config.json + tokenizer files (skip their download)")
    ap.add_argument("--local-dir", help="full: load the model from this local dir")
    args = ap.parse_args()

    entries = read_labels(args.labels)
    is_open_clip = args.model.startswith("hf-hub:") or args.model.startswith("local-dir:")
    # SigLIP/SigLIP2 were trained on lowercased text; CLIP-style BPE tokenizers (PE-Core) lowercase anyway.
    lowercase = not args.no_lowercase and "siglip" in args.model.lower()
    prompts, counts = [], []
    for _, phrases in entries:
        ps = prompts_for(phrases, args.templates, lowercase)
        prompts += ps
        counts.append(len(ps))
    print(f"{len(entries)} labels, {len(prompts)} prompts", file=sys.stderr)

    if is_open_clip:
        if args.mode == "sparse":
            sys.exit("--mode sparse supports SigLIP/SigLIP2 safetensors repos only")
        raw, scale, bias, family = run_open_clip(args, prompts)
    elif args.mode == "sparse":
        raw, scale, bias, family = run_sparse_siglip(args, prompts)
    else:
        raw, scale, bias, family = run_full_siglip(args, prompts)

    mat = pool(raw, counts)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    m16 = mat.astype("<f2")
    np.save(out.with_suffix(".npy"), m16)
    m16.tofile(out.with_suffix(".f16"))
    meta = {
        "model": args.model,
        "revision": args.revision,
        "commit": None if is_open_clip or args.weights else repo_commit(args.endpoint, args.model, args.revision),
        "family": family,
        "mode": args.mode,
        "labels": [l for l, _ in entries],
        "phrases": {l: p for l, p in entries},
        "templates": args.templates,
        "lowercase": lowercase,
        "count": int(mat.shape[0]),
        "dim": int(mat.shape[1]),
        "dtype": "float16 little-endian, row-major, rows L2-normalized",
        "logit_scale": scale,  # already exp()'d: p = sigmoid(logit_scale * cos + logit_bias) (SigLIP)
        "logit_bias": bias,
        "sha256_f16": hashlib.sha256(m16.tobytes()).hexdigest(),
        "note": "Use only with an image tower from the same checkpoint and resolution.",
    }
    out.with_suffix(".json").write_text(json.dumps(meta, indent=2))
    print(f"wrote {out}.npy/.f16/.json: {mat.shape[0]} x {mat.shape[1]}", file=sys.stderr)


if __name__ == "__main__":
    main()

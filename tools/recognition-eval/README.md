# Recognition evaluation tools

These scripts produced the numbers in [`docs/object-recognition.md`](../../docs/object-recognition.md).

They were run on one Mac with **hard-coded paths under `/tmp/claude-501/`**:
- `bench/` holds the dataset.
- `eval/` holds the outputs.
- `venv-eval/` holds Python.

Change the constants at the top of each script, or make those folders, to rerun them. No images, model weights or embeddings are committed; the scripts rebuild them.

## Setup

```sh
uv venv /tmp/claude-501/venv-eval --python 3.11
uv pip install --python /tmp/claude-501/venv-eval/bin/python torch open_clip_torch transformers timm sentencepiece pillow numpy coremltools
```

Run Python with `-I` (`/tmp/claude-501/venv-eval/bin/python -I script.py`).

The models download through open_clip / Hugging Face:
- PE-Core-S: `hf-hub:timm/PE-Core-S-16-384`, ~350 MB.
- CLIP-L/14 and SigLIP so400m are optional references.
- The YOLOE detector is the app's own `ios/Moove/Resources/Models/MooveObjects.mlpackage`, fetched by `ios/scripts/fetch-models.sh`.

## Layout

| Folder | What | Key files |
|---|---|---|
| `bench/` | Builds the benchmark: crops from Open Images / LVIS boxes plus Wikimedia photos, padded 10% and capped at 800 px, written as `manifest.jsonl` rows (`path`, `label`, `fine_label`, `source`, `license`, `split`) | `select.py` (pick boxes), `crop.py`, `commons.py` (Wikimedia, licence-filtered), `manifest.py`, `drop.txt` / `relabel.json` / `wm_keep.txt` (hand QC), `ipad_truth.tsv` (truth for our 120 iPad scan photos; the photos themselves are pulled from a device with `xcrun devicectl device copy from …`, see `docs/object-recognition.md`) |
| `eval/` | The benchmark runs | `vision_eval.swift` (YOLOE detector + `VNClassifyImageRequest` + feature-print kNN through Vision), `zs_eval.py` (zero-shot CLIP/PE-Core/SigLIP; `CLASSES`, `TEMPLATES`, negatives), `analyze.py` (all tables → `results.md`), `run_all.sh`, `size_check.py`, `results.md` (the full results) |
| `convert/` | PE-Core → Core ML and the shipped fused pipeline | `convert.py` (image tower to an 8-bit `ObjectClassifier.mlpackage`, cosine check vs PyTorch), `embed.swift` (embeds through Vision like the app), `fuse.py` (recorded label + recheck + size veto on the iPad split → `fuse_results.md`), `labels.py` (writes `ObjectClassifierLabels.*`) |
| `text-matrix/` | Label-embedding matrix for a SigLIP/PE-Core text tower, including a `--mode sparse` that range-downloads only the vocabulary rows it needs (~343 MB instead of 1.5 GB) | `make_text_matrix.py`, `labels.example.txt` |
| `research2/` | Prompts, few-shot probe, merges and size priors | `final_results.md` (best recipe), `fewshot*.py`, `loro.py` (leave-one-room-out), `adapter_classes.json` (the 62 shipped classes) |
| `research3/` | Multi-keyframe voting (projects scanned 3D boxes into saved keyframes) | `mv_common.py` (projection + occlusion), `mv_eval.py`, `mv_honest.py` (held-out-scan selection), `mv_results.md` |
| `research4/` | Recheck policy for RoomPlan objects (reject-only, 0.7) | `rp_policy.py`, `rp_policy_results.md` |
| `research5/` | Detector label → category fixes and per-label thresholds (not applied yet) | `final_out.md` (before/after), `proposal.py`, `sim.py` (keyframe tracking sim), `frames_det.swift` |

## Rerun the main tables

```sh
cd tools/recognition-eval/eval
./run_all.sh          # detector/Vision + zero-shot embeddings (skips steps whose outputs exist), then analyze.py
```

To add a model: write `zs_<key>.npz` with the fields `zs_eval.py` writes (`paths` in manifest order, `classes`, `labels`, `logits` [N,C], `emb` [N,D], `ms`, `device`), add a display name to `nm` in `analyze.py`, and rerun `analyze.py`. Every table picks it up, including the kNN and fusion rows.

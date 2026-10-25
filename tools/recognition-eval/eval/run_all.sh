#!/bin/zsh
# Re-runs the whole benchmark. Steps 1-2 are slow; skip them if their outputs exist.
set -e
E=/tmp/claude-501/eval; PY=(/tmp/claude-501/venv-eval/bin/python -I)
cd $E
[ -d model/MooveObjects.mlmodelc ] || xcrun coremlcompiler compile /Users/rioschillmoeller/moove/ios/Moove/Resources/Models/MooveObjects.mlpackage model/
[ -x vision_eval ] || swiftc -O vision_eval.swift -o vision_eval
[ -s vision_raw.jsonl ] || ./vision_eval /tmp/claude-501/bench/manifest.jsonl /tmp/claude-501/bench model/MooveObjects.mlmodelc > vision_raw.jsonl
[ -s zs_siglip-so400m.npz ] || "${PY[@]}" zs_eval.py siglip-so400m clip-l14
[ -s zs_pecore-s16.npz ] || { [ -s dl/pecore/open_clip_model.safetensors ] && "${PY[@]}" zs_eval.py pecore-s16 || true; }
[ -s zs_siglip2-b16.npz ] || { [ "$(stat -f %z dl/siglip2/open_clip_model.safetensors 2>/dev/null || echo 0)" -ge 1500786832 ] && "${PY[@]}" zs_eval.py siglip2-b16 || true; }
"${PY[@]}" analyze.py > /dev/null
{ echo; echo "## Crop size / vocabulary check (public split)"; echo; echo '```'; "${PY[@]}" size_check.py | sed -n '1,5p'; echo '```'; "${PY[@]}" size_check.py | sed -n '6,$p'; } >> results.md
echo "wrote $E/results.md"

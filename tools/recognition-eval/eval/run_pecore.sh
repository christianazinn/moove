#!/bin/zsh
# waits for the PE-Core-S weights download (348,787,644 bytes) and the HF zero-shot run, then runs PE-Core zero-shot
F=/tmp/claude-501/eval/dl/pecore/open_clip_model.safetensors
while [ "$(stat -f %z $F)" -lt 348787644 ]; do sleep 10; done
while pgrep -f "zs_eval.py siglip" >/dev/null; do sleep 10; done
/tmp/claude-501/venv-eval/bin/python -I /tmp/claude-501/eval/zs_eval.py pecore-s16

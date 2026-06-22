#!/bin/bash
set -euo pipefail

# =============================================================================
# Model Downloader — fetch GGUF from URL or HuggingFace
# =============================================================================

MODEL_PATH="${MODEL_PATH:-/workspace/models/model.gguf}"
MODEL_URL="${MODEL_URL:-}"
HF_REPO="${HF_REPO:-}"
HF_FILE="${HF_FILE:-}"
HF_TOKEN="${HF_TOKEN:-}"

mkdir -p "$(dirname "$MODEL_PATH")"

if [ -f "$MODEL_PATH" ]; then
    echo "[download] Model already exists at $MODEL_PATH, skipping."
    exit 0
fi

if [ -n "$MODEL_URL" ]; then
    echo "[download] Fetching from URL: $MODEL_URL"
    wget -c --progress=dot:giga -O "$MODEL_PATH" "$MODEL_URL"
    echo "[download] Done: $MODEL_PATH"

elif [ -n "$HF_REPO" ] && [ -n "$HF_FILE" ]; then
    echo "[download] Fetching from HuggingFace: $HF_REPO / $HF_FILE"
    pip install --no-cache-dir huggingface_hub
    python3 -c "
import os, shutil
from huggingface_hub import hf_hub_download
token = os.environ.get('HF_TOKEN') or None
path = hf_hub_download(
    repo_id='$HF_REPO',
    filename='$HF_FILE',
    token=token,
)
shutil.copy2(path, '$MODEL_PATH')
print(f'[download] Copied to $MODEL_PATH')
"

else
    echo "[download] ERROR: No MODEL_URL or HF_REPO+HF_FILE set."
    exit 1
fi

# Verify file
SIZE=$(stat -c%s "$MODEL_PATH" 2>/dev/null || stat -f%z "$MODEL_PATH")
echo "[download] Size: $((SIZE / 1073741824)) GB ($SIZE bytes)"
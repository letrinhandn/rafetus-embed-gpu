#!/usr/bin/env bash
# Bootstrap RunPod worker: install deps and start BGE-M3 embed handler.
set -euo pipefail
HANDLER_URL="${RAFETUS_HANDLER_URL:-https://raw.githubusercontent.com/letrinhandn/rafetus-embed-gpu/main/handler.py}"
pip install --no-cache-dir -q runpod~=1.7.6 "sentence-transformers>=3.0.0,<4.0.0"
curl -fsSL "${HANDLER_URL}" -o /handler.py
exec python -u /handler.py

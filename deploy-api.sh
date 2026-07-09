#!/usr/bin/env bash
# Deploy RunPod Serverless endpoint (no custom registry — uses public runpod/pytorch + GitHub handler).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}"
  exit 1
fi

set -a
source "${ENV_FILE}"
set +a

if [[ -z "${RUNPOD_API_KEY:-}" ]]; then
  echo "RUNPOD_API_KEY is not set in ${ENV_FILE}"
  exit 1
fi

TEMPLATE_NAME="${RUNPOD_TEMPLATE_NAME:-rafetus-embed-gpu}"
ENDPOINT_NAME="${RUNPOD_ENDPOINT_NAME:-rafetus-embed-bge-m3}"
HANDLER_URL="${RAFETUS_HANDLER_URL:-https://raw.githubusercontent.com/letrinhandn/rafetus-embed-gpu/main/handler.py}"
# Public RunPod CUDA image (no private registry push required).
IMAGE="${RUNPOD_BASE_IMAGE:-runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04}"
API="https://rest.runpod.io/v1"
AUTH="Authorization: Bearer ${RUNPOD_API_KEY}"

START_CMD="pip install --no-cache-dir --upgrade 'fastembed>=0.7.0' onnxruntime-gpu runpod==1.7.6 && curl -fsSL '${HANDLER_URL}' -o /handler.py && python -u /handler.py"

echo "==> Create or reuse serverless template (${IMAGE})"
EXISTING_TEMPLATE_ID="$(curl -sf "${API}/templates" -H "${AUTH}" | python3 -c "
import json, sys
name = sys.argv[1]
for t in json.load(sys.stdin):
    if t.get('name') == name and t.get('isServerless'):
        print(t['id'])
        break
" "${TEMPLATE_NAME}" 2>/dev/null || true)"

TEMPLATE_PAYLOAD="$(python3 -c "
import json
print(json.dumps({
  'name': '${TEMPLATE_NAME}',
  'imageName': '${IMAGE}',
  'isServerless': True,
  'containerDiskInGb': 20,
  'dockerStartCmd': ['bash', '-c', '''${START_CMD}'''],
  'env': {
    'EMBED_MODEL': 'BAAI/bge-m3',
    'EMBED_BATCH_SIZE': '128',
    'HF_HOME': '/runpod-volume',
    'TRANSFORMERS_CACHE': '/runpod-volume',
  },
}))
")"

if [[ -n "${EXISTING_TEMPLATE_ID}" ]]; then
  TEMPLATE_ID="${EXISTING_TEMPLATE_ID}"
  echo "    Reusing template ${TEMPLATE_ID}"
  curl -s -X PATCH "${API}/templates/${TEMPLATE_ID}" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${TEMPLATE_PAYLOAD}" >/dev/null || true
else
  TEMPLATE_RESP="$(curl -sf -X POST "${API}/templates" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${TEMPLATE_PAYLOAD}")"
  TEMPLATE_ID="$(echo "${TEMPLATE_RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
  echo "    Created template ${TEMPLATE_ID}"
fi

echo "==> Create or reuse endpoint (RTX 4090)"
EXISTING_ENDPOINT_ID="$(curl -s "${API}/endpoints" -H "${AUTH}" | python3 -c "
import json, sys
name = sys.argv[1]
for e in json.load(sys.stdin):
    if e.get('name') == name:
        print(e['id'])
        break
" "${ENDPOINT_NAME}" 2>/dev/null || true)"

ENDPOINT_BODY="$(python3 -c "
import json
print(json.dumps({
  'name': '${ENDPOINT_NAME}',
  'templateId': '${TEMPLATE_ID}',
  'gpuTypeIds': ['NVIDIA GeForce RTX 4090'],
  'workersMin': 0,
  'workersMax': 3,
  'idleTimeout': 10,
  'executionTimeoutMs': 300000,
  'flashboot': True,
  'scalerType': 'QUEUE_DELAY',
  'scalerValue': 4,
}))
")"

if [[ -n "${EXISTING_ENDPOINT_ID}" ]]; then
  ENDPOINT_ID="${EXISTING_ENDPOINT_ID}"
  echo "    Updating endpoint ${ENDPOINT_ID}"
  curl -s -X PATCH "${API}/endpoints/${ENDPOINT_ID}" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${ENDPOINT_BODY}" >/dev/null || true
else
  ENDPOINT_RESP="$(curl -s -X POST "${API}/endpoints" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${ENDPOINT_BODY}")"
  if echo "${ENDPOINT_RESP}" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('id') else 1)" 2>/dev/null; then
    ENDPOINT_ID="$(echo "${ENDPOINT_RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
    echo "    Created endpoint ${ENDPOINT_ID}"
  else
    echo "    Endpoint create failed: ${ENDPOINT_RESP}"
    echo ""
    echo "RunPod requires at least \$0.01 balance. Load credits at https://www.runpod.io/console/user/billing"
    echo "Then re-run: bash runpod/deploy-api.sh"
    echo ""
    python3 - <<PY
from pathlib import Path
import re
path = Path("${ENV_FILE}")
text = path.read_text()
key = "RUNPOD_TEMPLATE_ID"
val = "${TEMPLATE_ID}"
if re.search(rf"^{key}=", text, re.M):
    text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, flags=re.M)
else:
    text = text.rstrip() + f"\n{key}={val}\n"
path.write_text(text)
PY
    exit 1
  fi
fi

echo "==> Smoke test /runsync (cold start 2-4 min first time)"
TEST_RESP="$(curl -sf -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/runsync" \
  -H "${AUTH}" -H "Content-Type: application/json" \
  -d '{"input":{"texts":["xin chào","hello world"],"normalize":true}}' \
  --max-time 600)"
echo "${TEST_RESP}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data.get('status') == 'FAILED':
    raise SystemExit(data.get('error') or 'RunPod job failed')
out = data.get('output') or data
vecs = out.get('vectors') or []
if not vecs:
    raise SystemExit(f'No vectors in response: {json.dumps(data)[:500]}')
print(f'OK: {out.get(\"count\", len(vecs))} vectors, dim={out.get(\"dim\", len(vecs[0]))}')
"

python3 - <<PY
from pathlib import Path
import re
path = Path("${ENV_FILE}")
text = path.read_text()
updates = {
    "RUNPOD_EMBED_ENDPOINT_ID": "${ENDPOINT_ID}",
    "INGEST_EMBED_BACKEND": "runpod",
}
for key, val in updates.items():
    if re.search(rf"^{key}=", text, re.M):
        text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, flags=re.M)
    else:
        text = text.rstrip() + f"\n{key}={val}\n"
path.write_text(text)
PY

echo ""
echo "Deployed."
echo "  Endpoint ID: ${ENDPOINT_ID}"
echo "  URL: https://api.runpod.ai/v2/${ENDPOINT_ID}/runsync"
echo "  Handler: ${HANDLER_URL}"
echo "  .env updated"

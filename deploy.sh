#!/usr/bin/env bash
# Build, push, and deploy Rafetus BGE-M3 embed worker to RunPod Serverless.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
RUNPOD_DIR="${ROOT}/runpod"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE} — set RUNPOD_API_KEY there first."
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

if [[ -z "${RUNPOD_API_KEY:-}" ]]; then
  echo "RUNPOD_API_KEY is not set in ${ENV_FILE}"
  exit 1
fi

GH_USER="${GHCR_USER:-letrinhandn}"
IMAGE="${RUNPOD_EMBED_IMAGE:-ghcr.io/${GH_USER}/rafetus-embed-gpu:latest}"
TEMPLATE_NAME="${RUNPOD_TEMPLATE_NAME:-rafetus-embed-gpu}"
ENDPOINT_NAME="${RUNPOD_ENDPOINT_NAME:-rafetus-embed-bge-m3}"
API="https://rest.runpod.io/v1"
AUTH="Authorization: Bearer ${RUNPOD_API_KEY}"

echo "==> Docker login GHCR"
gh auth token | docker login ghcr.io -u "${GH_USER}" --password-stdin

echo "==> Build ${IMAGE} (linux/amd64)"
docker buildx build --platform linux/amd64 \
  -f "${RUNPOD_DIR}/Dockerfile" \
  -t "${IMAGE}" \
  "${RUNPOD_DIR}" \
  --load

echo "==> Push ${IMAGE}"
if ! docker push "${IMAGE}" 2>/dev/null; then
  echo "    Push failed (GHCR scope or Docker Hub auth). Falling back to deploy-api.sh (public base image + GitHub handler)."
  exec bash "${RUNPOD_DIR}/deploy-api.sh"
fi

echo "==> Make GHCR package public (RunPod pull without auth)"
PKG="rafetus-embed-gpu"
if gh api "users/${GH_USER}/packages/container/${PKG}" >/dev/null 2>&1; then
  gh api --method PATCH "users/${GH_USER}/packages/container/${PKG}" \
    -f visibility=public >/dev/null || true
fi

echo "==> Create or reuse serverless template"
EXISTING_TEMPLATE_ID="$(curl -sf "${API}/templates" -H "${AUTH}" | python3 -c "
import json, sys
name = sys.argv[1]
for t in json.load(sys.stdin):
    if t.get('name') == name and t.get('isServerless'):
        print(t['id'])
        break
" "${TEMPLATE_NAME}" 2>/dev/null || true)"

if [[ -n "${EXISTING_TEMPLATE_ID}" ]]; then
  TEMPLATE_ID="${EXISTING_TEMPLATE_ID}"
  echo "    Reusing template ${TEMPLATE_ID}"
  curl -sf -X PATCH "${API}/templates/${TEMPLATE_ID}" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
  'imageName': '${IMAGE}',
  'containerDiskInGb': 20,
  'isServerless': True,
  'env': {
    'EMBED_MODEL': 'BAAI/bge-m3',
    'EMBED_BATCH_SIZE': '128',
  },
}))
")" >/dev/null
else
  TEMPLATE_RESP="$(curl -sf -X POST "${API}/templates" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
  'name': '${TEMPLATE_NAME}',
  'imageName': '${IMAGE}',
  'isServerless': True,
  'containerDiskInGb': 20,
  'env': {
    'EMBED_MODEL': 'BAAI/bge-m3',
    'EMBED_BATCH_SIZE': '128',
  },
}))
")")"
  TEMPLATE_ID="$(echo "${TEMPLATE_RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
  echo "    Created template ${TEMPLATE_ID}"
fi

echo "==> Create or reuse endpoint"
EXISTING_ENDPOINT_ID="$(curl -sf "${API}/endpoints" -H "${AUTH}" | python3 -c "
import json, sys
name = sys.argv[1]
for e in json.load(sys.stdin):
    if e.get('name') == name:
        print(e['id'])
        break
" "${ENDPOINT_NAME}" 2>/dev/null || true)"

WORKERS_MIN="${RUNPOD_WORKERS_MIN:-0}"
WORKERS_MAX="${RUNPOD_WORKERS_MAX:-1}"
IDLE_TIMEOUT="${RUNPOD_IDLE_TIMEOUT:-45}"
SCALER_TYPE="${RUNPOD_SCALER_TYPE:-QUEUE_DELAY}"
SCALER_VALUE="${RUNPOD_SCALER_VALUE:-8}"
ENDPOINT_BODY="$(python3 -c "
import json
print(json.dumps({
  'name': '${ENDPOINT_NAME}',
  'templateId': '${TEMPLATE_ID}',
  'gpuTypeIds': [
    'NVIDIA GeForce RTX 4090',
    'NVIDIA RTX A5000',
    'NVIDIA A40',
  ],
  'workersMin': int('${WORKERS_MIN}'),
  'workersMax': int('${WORKERS_MAX}'),
  'idleTimeout': int('${IDLE_TIMEOUT}'),
  'executionTimeoutMs': 600000,
  'flashboot': True,
  'scalerType': '${SCALER_TYPE}',
  'scalerValue': int('${SCALER_VALUE}'),
}))
")"

if [[ -n "${EXISTING_ENDPOINT_ID}" ]]; then
  ENDPOINT_ID="${EXISTING_ENDPOINT_ID}"
  echo "    Updating endpoint ${ENDPOINT_ID}"
  curl -sf -X PATCH "${API}/endpoints/${ENDPOINT_ID}" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${ENDPOINT_BODY}" >/dev/null
else
  ENDPOINT_RESP="$(curl -sf -X POST "${API}/endpoints" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d "${ENDPOINT_BODY}")"
  ENDPOINT_ID="$(echo "${ENDPOINT_RESP}" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")"
  echo "    Created endpoint ${ENDPOINT_ID}"
fi

echo "==> Smoke test /runsync (cold start may take 1-2 min)"
TEST_RESP="$(curl -sf -X POST "https://api.runpod.ai/v2/${ENDPOINT_ID}/runsync" \
  -H "${AUTH}" -H "Content-Type: application/json" \
  -d '{"input":{"texts":["xin chào","hello world"],"normalize":true}}' \
  --max-time 300)"
echo "${TEST_RESP}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
out = data.get('output') or data
vecs = out.get('vectors') or []
print(f'OK: {out.get(\"count\", len(vecs))} vectors, dim={out.get(\"dim\", len(vecs[0]) if vecs else 0)}')
"

# Update .env with endpoint id (idempotent)
python3 - <<PY
from pathlib import Path
import re
path = Path("${ENV_FILE}")
text = path.read_text()
key = "RUNPOD_EMBED_ENDPOINT_ID"
val = "${ENDPOINT_ID}"
if re.search(rf"^{key}=", text, re.M):
    text = re.sub(rf"^{key}=.*$", f"{key}={val}", text, flags=re.M)
else:
    text = text.rstrip() + f"\n{key}={val}\n"
if "INGEST_EMBED_BACKEND=runpod" not in text:
    if re.search(r"^INGEST_EMBED_BACKEND=", text, re.M):
        text = re.sub(r"^INGEST_EMBED_BACKEND=.*$", "INGEST_EMBED_BACKEND=runpod", text, flags=re.M)
    else:
        text = text.rstrip() + "\nINGEST_EMBED_BACKEND=runpod\n"
path.write_text(text)
PY

echo ""
echo "Deployed."
echo "  Endpoint ID: ${ENDPOINT_ID}"
echo "  URL: https://api.runpod.ai/v2/${ENDPOINT_ID}/runsync"
echo "  .env updated: RUNPOD_EMBED_ENDPOINT_ID, INGEST_EMBED_BACKEND=runpod"
echo "  Restart ar-worker-embed to pick up remote GPU embed."

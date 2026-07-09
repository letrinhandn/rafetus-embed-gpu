#!/usr/bin/env bash
# Patch live RunPod endpoint for max-out ingest (needs REST/full-access API key).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

# Prefer management key for rest.runpod.io; fall back to RUNPOD_API_KEY.
API_KEY="${RUNPOD_MANAGEMENT_API_KEY:-${RUNPOD_API_KEY:-}}"
ENDPOINT_ID="${RUNPOD_EMBED_ENDPOINT_ID:-}"
TEMPLATE_ID="${RUNPOD_TEMPLATE_ID:-}"

if [[ -z "${API_KEY}" || -z "${ENDPOINT_ID}" ]]; then
  echo "Need RUNPOD_API_KEY (or RUNPOD_MANAGEMENT_API_KEY) and RUNPOD_EMBED_ENDPOINT_ID"
  exit 1
fi

API="https://rest.runpod.io/v1"
AUTH="Authorization: Bearer ${API_KEY}"
WORKERS_MIN="${RUNPOD_WORKERS_MIN:-1}"
# Account worker quota is often 10 — default 8 leaves headroom.
WORKERS_MAX="${RUNPOD_WORKERS_MAX:-8}"
IDLE_TIMEOUT="${RUNPOD_IDLE_TIMEOUT:-120}"

BODY="$(python3 -c "
import json
body = {
  'workersMin': int('${WORKERS_MIN}'),
  'workersMax': int('${WORKERS_MAX}'),
  'idleTimeout': int('${IDLE_TIMEOUT}'),
  'executionTimeoutMs': 600000,
  'flashboot': True,
  'scalerType': 'REQUEST_COUNT',
  'scalerValue': 1,
  'gpuTypeIds': [
    'NVIDIA GeForce RTX 4090',
    'NVIDIA GeForce RTX 5090',
    'NVIDIA A40',
  ],
}
if '${TEMPLATE_ID}':
    body['templateId'] = '${TEMPLATE_ID}'
print(json.dumps(body))
")"

echo "==> PATCH endpoint ${ENDPOINT_ID}"
HTTP_CODE="$(curl -s -o /tmp/runpod-patch.json -w "%{http_code}" -X PATCH "${API}/endpoints/${ENDPOINT_ID}" \
  -H "${AUTH}" -H "Content-Type: application/json" \
  -d "${BODY}")"
if ! python3 -c "
import json, sys
from pathlib import Path
raw = Path('/tmp/runpod-patch.json').read_text()
d = json.loads(raw)
if d.get('error') or d.get('status') == 400:
    print(raw[:800])
    sys.exit(1)
print('workersMin=', d.get('workersMin'), 'workersMax=', d.get('workersMax'))
print('scalerType=', d.get('scalerType'), 'scalerValue=', d.get('scalerValue'))
print('idleTimeout=', d.get('idleTimeout'), 'flashboot=', d.get('flashboot'))
print('gpuTypeIds=', d.get('gpuTypeIds'))
"; then
  echo "PATCH failed HTTP=${HTTP_CODE}"
  head -c 500 /tmp/runpod-patch.json
  exit 1
fi

if [[ -n "${TEMPLATE_ID}" ]]; then
  echo "==> PATCH template ${TEMPLATE_ID} EMBED_BATCH_SIZE=256"
  curl -s -X PATCH "${API}/templates/${TEMPLATE_ID}" \
    -H "${AUTH}" -H "Content-Type: application/json" \
    -d '{"env":{"EMBED_MODEL":"BAAI/bge-m3","EMBED_BATCH_SIZE":"256","HF_HOME":"/runpod-volume","TRANSFORMERS_CACHE":"/runpod-volume"}}' \
    >/dev/null || true
fi

echo "==> Health"
curl -s "https://api.runpod.ai/v2/${ENDPOINT_ID}/health" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY:-${API_KEY}}" | python3 -m json.tool
echo "Done."

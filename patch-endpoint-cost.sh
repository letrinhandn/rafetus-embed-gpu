#!/usr/bin/env bash
# Cost-efficient RunPod: scale-to-zero, 1 GPU, QUEUE_DELAY, short idle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ROOT}/.env"
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

API_KEY="${RUNPOD_MANAGEMENT_API_KEY:-${RUNPOD_API_KEY:-}}"
ENDPOINT_ID="${RUNPOD_EMBED_ENDPOINT_ID:-}"
TEMPLATE_ID="${RUNPOD_TEMPLATE_ID:-}"

if [[ -z "${API_KEY}" || -z "${ENDPOINT_ID}" ]]; then
  echo "Need RUNPOD_MANAGEMENT_API_KEY (or RUNPOD_API_KEY) and RUNPOD_EMBED_ENDPOINT_ID"
  exit 1
fi

API="https://rest.runpod.io/v1"
AUTH="Authorization: Bearer ${API_KEY}"
WORKERS_MIN="${RUNPOD_WORKERS_MIN:-0}"
WORKERS_MAX="${RUNPOD_WORKERS_MAX:-1}"
IDLE_TIMEOUT="${RUNPOD_IDLE_TIMEOUT:-45}"
SCALER_TYPE="${RUNPOD_SCALER_TYPE:-QUEUE_DELAY}"
SCALER_VALUE="${RUNPOD_SCALER_VALUE:-8}"

BODY="$(python3 -c "
import json
body = {
  'workersMin': int('${WORKERS_MIN}'),
  'workersMax': int('${WORKERS_MAX}'),
  'idleTimeout': int('${IDLE_TIMEOUT}'),
  'executionTimeoutMs': 600000,
  'flashboot': True,
  'scalerType': '${SCALER_TYPE}',
  'scalerValue': int('${SCALER_VALUE}'),
  'gpuTypeIds': [
    'NVIDIA GeForce RTX 4090',
    'NVIDIA RTX A5000',
    'NVIDIA A40',
  ],
}
if '${TEMPLATE_ID}':
    body['templateId'] = '${TEMPLATE_ID}'
print(json.dumps(body))
")"

echo "==> PATCH endpoint ${ENDPOINT_ID} (cost-efficient)"
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

echo "==> Health"
curl -s "https://api.runpod.ai/v2/${ENDPOINT_ID}/health" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY:-${API_KEY}}" | python3 -m json.tool
echo "Done. Idle GPU will scale to 0 after ~${IDLE_TIMEOUT}s."

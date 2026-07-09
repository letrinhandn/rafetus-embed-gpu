# Rafetus RunPod Serverless — BGE-M3 GPU embed

Stateless GPU worker for ingest embedding. `ar-worker-embed` (CPU) polls SQS and calls this endpoint per batch.

## Quick deploy

1. Set `RUNPOD_API_KEY` in `rafetus-index/.env`
2. **Load ≥ $0.01 credits** on [RunPod billing](https://www.runpod.io/console/user/billing)
3. Run:

```bash
cd rafetus-index
bash runpod/deploy-api.sh
```

This creates/updates:
- Serverless template `rafetus-embed-gpu` (public `runpod/pytorch` + handler from GitHub)
- Endpoint `rafetus-embed-bge-m3` on **RTX 4090**
- `.env` keys: `RUNPOD_EMBED_ENDPOINT_ID`, `INGEST_EMBED_BACKEND=runpod`

## Custom image (optional)

If you have GHCR/Docker Hub push access:

```bash
bash runpod/deploy.sh   # build + push ghcr.io/<user>/rafetus-embed-gpu
```

## Worker env (ar-worker-embed)

```bash
INGEST_EMBED_BACKEND=runpod
RUNPOD_API_KEY=rpa_...
RUNPOD_EMBED_ENDPOINT_ID=<from deploy output>
INGEST_EMBED_PARTIAL_BATCH=128
```

Restart embed worker after deploy:

```bash
cd rafetus-web-app
docker compose up -d ar-worker-embed
```

## Test endpoint

```bash
source .env
curl -X POST "https://api.runpod.ai/v2/${RUNPOD_EMBED_ENDPOINT_ID}/runsync" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"input":{"texts":["xin chào","hello"],"normalize":true}}'
```

Handler source: https://github.com/letrinhandn/rafetus-embed-gpu

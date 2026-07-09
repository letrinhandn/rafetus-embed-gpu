# Rafetus RunPod Serverless — BGE-M3 (cost-efficient)

**Mục tiêu:** cực rẻ + đủ nhanh. Không giữ GPU 24/7, không bung nhiều worker.

## Cấu hình chốt

```
RunPod:
  workersMin: 0
  workersMax: 1
  scalerType: QUEUE_DELAY
  scalerValue: 8
  idleTimeout: 45
  GPU: RTX 4090 (+ A5000 / A40 fallback)

App:
  INGEST_WORKER_CONCURRENCY: 1   # embed + extract + index
  RUNPOD_EMBED_SHARD_SIZE: 256   # thử 384/512 sau khi bake image
  RUNPOD_EMBED_MAX_PARALLEL: 1
  feeder per-user cap: 1
  sweeper republish: false
```

Patch endpoint:

```bash
bash runpod/patch-endpoint-cost.sh
```

## Bake image (khuyến nghị — bỏ pip/model download lúc boot)

```bash
bash runpod/deploy.sh
```

Dockerfile bake deps + BGE-M3. Bootstrap `deploy-api.sh` vẫn pip-on-boot → chỉ dùng tạm.

## Worker env

```bash
INGEST_EMBED_BACKEND=runpod
RUNPOD_API_KEY=rpa_...              # inference
RUNPOD_MANAGEMENT_API_KEY=rpa_...   # REST patch
RUNPOD_EMBED_ENDPOINT_ID=<id>
RUNPOD_EMBED_SHARD_SIZE=256
RUNPOD_EMBED_MAX_PARALLEL=1
```

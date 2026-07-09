# Rafetus RunPod Serverless — BGE-M3 GPU embed (cost-efficient)

Stateless GPU worker for ingest embedding. Design goal: **cực rẻ + đủ nhanh**, không giữ GPU 24/7.

## Chốt cấu hình Rafetus

```
RunPod:
  workersMin: 0          # scale-to-zero — $0 khi không ingest
  workersMax: 1          # đúng 1 GPU đầy tải
  scalerType: QUEUE_DELAY
  scalerValue: 8         # giây
  idleTimeout: 45        # tắt sau khi hết việc
  GPU: RTX 4090 (+ A5000/A40 fallback)

App:
  INGEST_WORKER_CONCURRENCY: 2
  RUNPOD_EMBED_SHARD_SIZE: 256   # thử 384/512 sau benchmark
  RUNPOD_EMBED_MAX_PARALLEL: 1   # tối đa 2 — không fan-out 8 GPU
  feeder per-user cap: 2
```

## Patch endpoint đang chạy

```bash
# Needs RUNPOD_MANAGEMENT_API_KEY (full REST) in rafetus-index/.env
bash runpod/patch-endpoint-cost.sh
```

## Deploy

**Bootstrap (không cần registry)** — `deploy-api.sh` vẫn `pip install` lúc boot → cold start chậm hơn. Chỉ dùng khi chưa push được image bake.

**Bake (khuyến nghị)** — Dockerfile cài deps + tải BGE-M3 sẵn:

```bash
bash runpod/deploy.sh   # build + push + update endpoint
```

## Worker env

```bash
INGEST_EMBED_BACKEND=runpod
RUNPOD_API_KEY=rpa_...                 # inference
RUNPOD_MANAGEMENT_API_KEY=rpa_...      # rest.runpod.io patch/deploy
RUNPOD_EMBED_ENDPOINT_ID=<id>
INGEST_EMBED_PARTIAL_BATCH=256
RUNPOD_EMBED_SHARD_SIZE=256
RUNPOD_EMBED_MAX_PARALLEL=1
```

```bash
cd rafetus-web-app && docker compose up -d ar-worker-embed data-api
```

Handler: https://github.com/letrinhandn/rafetus-embed-gpu

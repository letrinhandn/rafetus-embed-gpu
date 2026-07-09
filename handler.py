"""RunPod Serverless worker — BGE-M3 via fastembed ONNX (matches Rust ingest path)."""

from __future__ import annotations

import logging
import os

import runpod

logger = logging.getLogger("rafetus.embed")

_model = None
_batch_size = int(os.environ.get("EMBED_BATCH_SIZE", "128"))


def _load_model():
    global _model
    if _model is not None:
        return _model
    from fastembed import TextEmbedding

    model_name = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")
    logger.info("Loading fastembed %s ...", model_name)
    _model = TextEmbedding(model_name=model_name)
    logger.info("fastembed model ready")
    return _model


def handler(job: dict) -> dict:
    inp = job.get("input") or {}
    texts = inp.get("texts") or []
    normalize = bool(inp.get("normalize", True))
    if not texts:
        return {"vectors": [], "dim": 1024, "count": 0}

    model = _load_model()
    vectors = []
    for start in range(0, len(texts), _batch_size):
        batch = texts[start : start + _batch_size]
        for emb in model.embed(batch):
            vec = emb.tolist() if hasattr(emb, "tolist") else list(emb)
            if normalize:
                import math

                norm = math.sqrt(sum(x * x for x in vec)) or 1.0
                vec = [x / norm for x in vec]
            vectors.append(vec)

    dim = len(vectors[0]) if vectors else 1024
    return {"vectors": vectors, "dim": dim, "count": len(texts)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    runpod.serverless.start({"handler": handler})

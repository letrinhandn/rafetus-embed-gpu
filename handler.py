"""RunPod Serverless worker — BGE-M3 via FlagEmbedding on GPU."""

from __future__ import annotations

import logging
import math
import os

import runpod

logger = logging.getLogger("rafetus.embed")

_model = None
_batch_size = int(os.environ.get("EMBED_BATCH_SIZE", "128"))


def _load_model():
    global _model
    if _model is not None:
        return _model
    import torch
    from FlagEmbedding import BGEM3FlagModel

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model_name = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")
    logger.info("Loading FlagEmbedding %s on %s ...", model_name, device)
    _model = BGEM3FlagModel(model_name, use_fp16=(device == "cuda"), device=device)
    logger.info("FlagEmbedding model ready")
    return _model


def _normalize(vec: list[float]) -> list[float]:
    norm = math.sqrt(sum(x * x for x in vec)) or 1.0
    return [x / norm for x in vec]


def handler(job: dict) -> dict:
    inp = job.get("input") or {}
    texts = inp.get("texts") or []
    normalize = bool(inp.get("normalize", True))
    if not texts:
        return {"vectors": [], "dim": 1024, "count": 0}

    model = _load_model()
    encoded = model.encode(
        texts,
        batch_size=min(_batch_size, len(texts)),
        max_length=1024,
    )
    dense = encoded.get("dense_vecs") if isinstance(encoded, dict) else encoded
    vectors = []
    for row in dense:
        vec = row.tolist() if hasattr(row, "tolist") else list(row)
        if normalize:
            vec = _normalize(vec)
        vectors.append(vec)

    dim = len(vectors[0]) if vectors else 1024
    return {"vectors": vectors, "dim": dim, "count": len(texts)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    runpod.serverless.start({"handler": handler})

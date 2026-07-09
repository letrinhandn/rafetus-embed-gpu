"""RunPod Serverless worker — BGE-M3 passage embeddings on GPU."""

from __future__ import annotations

import logging
import os

import runpod

logger = logging.getLogger("rafetus.embed")

_model = None
_batch_size = int(os.environ.get("EMBED_BATCH_SIZE", "128"))
_model_name = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")


def _load_model():
    global _model
    if _model is not None:
        return _model
    import torch
    from sentence_transformers import SentenceTransformer

    device = "cuda" if torch.cuda.is_available() else "cpu"
    logger.info("Loading %s on %s ...", _model_name, device)
    _model = SentenceTransformer(_model_name, device=device)
    logger.info("Model ready on %s", device)
    return _model


def handler(job: dict) -> dict:
    inp = job.get("input") or {}
    texts = inp.get("texts") or []
    normalize = bool(inp.get("normalize", True))
    if not texts:
        return {"vectors": [], "dim": 1024, "count": 0}

    model = _load_model()
    vectors = model.encode(
        texts,
        batch_size=min(_batch_size, len(texts)),
        normalize_embeddings=normalize,
        show_progress_bar=False,
    )
    dim = int(vectors.shape[1]) if len(vectors) else 1024
    return {
        "vectors": vectors.tolist(),
        "dim": dim,
        "count": len(texts),
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    runpod.serverless.start({"handler": handler})

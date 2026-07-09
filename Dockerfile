FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

WORKDIR /

# Bake deps — never pip-install at worker boot.
RUN pip install --no-cache-dir \
    runpod==1.7.6 \
    transformers==4.44.2 \
    sentence-transformers==3.0.1 \
    huggingface-hub==0.24.7 \
    tokenizers==0.19.1

COPY handler.py /handler.py

ENV EMBED_MODEL=BAAI/bge-m3
ENV EMBED_BATCH_SIZE=256
ENV HF_HOME=/models
ENV TRANSFORMERS_CACHE=/models
ENV HUGGINGFACE_HUB_CACHE=/models

# Bake BGE-M3 into the image so cold start does not re-download weights.
RUN python - <<'PY'
from sentence_transformers import SentenceTransformer
import os
name = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")
print(f"Baking {name} ...")
m = SentenceTransformer(name)
# Touch encode once so tokenizer/cache is warm in the layer.
_ = m.encode(["warmup"], normalize_embeddings=True)
print("Bake OK", name)
PY

CMD ["python", "-u", "/handler.py"]

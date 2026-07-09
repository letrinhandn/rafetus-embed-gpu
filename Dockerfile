FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

WORKDIR /

# Pin versions compatible with base torch 2.4 — do NOT force-reinstall torch/torchvision.
RUN pip install --no-cache-dir \
    runpod==1.7.6 \
    transformers==4.44.2 \
    sentence-transformers==3.0.1 \
    huggingface-hub==0.24.7 \
    tokenizers==0.19.1

COPY handler.py /handler.py

ENV EMBED_MODEL=BAAI/bge-m3
ENV EMBED_BATCH_SIZE=128
ENV HF_HOME=/runpod-volume
ENV TRANSFORMERS_CACHE=/runpod-volume

CMD ["python", "-u", "/handler.py"]

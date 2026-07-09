FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-runtime

WORKDIR /

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

COPY handler.py /handler.py

ENV EMBED_MODEL=BAAI/bge-m3
ENV EMBED_BATCH_SIZE=128
ENV HF_HOME=/runpod-volume
ENV TRANSFORMERS_CACHE=/runpod-volume

CMD ["python", "-u", "/handler.py"]

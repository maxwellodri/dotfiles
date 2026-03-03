FROM python:3.11-slim

RUN pip install --no-cache-dir faster-whisper

RUN mkdir -p /transcribe /models

RUN python -c "from faster_whisper import WhisperModel; WhisperModel('base', device='cpu', compute_type='int8', download_root='/models')"

WORKDIR /transcribe

CMD ["sleep", "infinity"]

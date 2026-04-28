FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY src ./src
COPY scripts ./scripts
COPY .env.example ./.env.example

RUN mkdir -p /app/data

EXPOSE 8000

CMD ["uvicorn", "sre_copilot.api:app", "--host", "0.0.0.0", "--port", "8000"]

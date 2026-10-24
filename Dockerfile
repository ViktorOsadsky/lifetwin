FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app
RUN pip install --no-cache-dir uv==0.13.5
COPY pyproject.toml uv.lock ./
COPY server ./server
RUN uv sync --frozen --no-dev --no-editable \
    && useradd --create-home --uid 10001 lifetwin \
    && chown -R lifetwin:lifetwin /app

USER lifetwin
EXPOSE 8000
CMD ["sh", "-c", "exec uvicorn lifetwin.app:app --host 0.0.0.0 --port ${PORT:-8000} --no-access-log"]

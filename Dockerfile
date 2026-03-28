# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

# Install Poetry
RUN pip install --no-cache-dir poetry

WORKDIR /app

# Copy dependency files first for layer caching
COPY pyproject.toml poetry.lock ./

# Install deps into a local venv (no dev deps, no project itself)
RUN poetry config virtualenvs.in-project true && \
    poetry install --no-root --without dev

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.11-slim

# OCI labels
LABEL org.opencontainers.image.title="tokenlean" \
      org.opencontainers.image.description="Token-reduction proxy stack: aip-proxy + LiteLLM → GitHub Copilot API" \
      org.opencontainers.image.url="https://github.com/gdilo/tokenlean" \
      org.opencontainers.image.source="https://github.com/gdilo/tokenlean" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Copy virtualenv from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application files
COPY copilot-config.yaml configure_claude.py savings.py entrypoint.sh ./

# Make venv binaries available
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

EXPOSE 4444 4445

# Health check on aip-proxy endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:4444/health', timeout=4)" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

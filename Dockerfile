# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Copy only dependency manifest for layer caching
COPY pyproject.toml ./

# Install deps into a local venv using pip (no poetry.lock required)
RUN python3 -m venv .venv && \
    .venv/bin/pip install --no-cache-dir --upgrade pip && \
    .venv/bin/pip install --no-cache-dir "litellm[proxy]>=1.0.0" "aip-proxy>=0.1.0" \
        "psutil>=5.9.0" "requests>=2.31.0" "dnspython>=2.4.0"

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

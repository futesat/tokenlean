# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Make Python and Poetry environment variables, no venv needed on container.
ENV PYTHONUNBUFFERED=1 \
    POETRY_VERSION=2.1.1 \
    POETRY_HOME="/opt/poetry" \
    POETRY_VIRTUALENVS_CREATE=false

ENV PATH="$POETRY_HOME/bin:$PATH"

# Copy only dependency manifest for layer caching
COPY pyproject.toml ./

#Update system and install poetry
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && pip install poetry==$POETRY_VERSION \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install deps into a local venv using pip (no poetry.lock required)
RUN poetry install --no-ansi --no-root --no-interaction

# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM builder as runtime

# OCI labels
LABEL org.opencontainers.image.title="tokenlean" \
    org.opencontainers.image.description="Token-reduction proxy stack: aip-proxy + LiteLLM → GitHub Copilot API" \
    org.opencontainers.image.url="https://github.com/gdilo/tokenlean" \
    org.opencontainers.image.source="https://github.com/gdilo/tokenlean" \
    org.opencontainers.image.licenses="MIT"

# Copy application files
COPY copilot-config.yaml configure_claude.py savings.py entrypoint.sh ./

EXPOSE 4444 4445

# Health check on aip-proxy endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:4444/health', timeout=4)" || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]

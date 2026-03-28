#!/bin/sh
# entrypoint.sh — starts LiteLLM then aip-proxy, handles graceful shutdown

set -e

LITELLM_PORT=4445
AIP_PORT=4444

# ── Graceful shutdown ─────────────────────────────────────────────────────────
shutdown() {
    echo "Received SIGTERM — shutting down..."
    [ -n "$LITELLM_PID" ] && kill "$LITELLM_PID" 2>/dev/null || true
    [ -n "$AIP_PID" ]     && kill "$AIP_PID"     2>/dev/null || true
    wait
    echo "Done."
    exit 0
}
trap shutdown TERM INT

# ── Start LiteLLM ─────────────────────────────────────────────────────────────
echo "Starting LiteLLM on :${LITELLM_PORT}..."
litellm --config /app/copilot-config.yaml --port "$LITELLM_PORT" &
LITELLM_PID=$!

# ── Wait for LiteLLM to be ready (up to 30s) ─────────────────────────────────
echo "Waiting for LiteLLM to be ready..."
i=0
while [ "$i" -lt 30 ]; do
    if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('localhost',$LITELLM_PORT))==0 else 1)" 2>/dev/null; then
        break
    fi
    sleep 1
    i=$((i+1))
done
if [ "$i" -ge 30 ]; then
    echo "ERROR: LiteLLM did not start within 30 seconds" >&2
    exit 1
fi
echo "  LiteLLM ready."

# ── Start aip-proxy (foreground) ─────────────────────────────────────────────
echo "Starting aip-proxy on :${AIP_PORT}..."
aip-proxy start --target "http://localhost:${LITELLM_PORT}" --port "$AIP_PORT" &
AIP_PID=$!

echo "  Both services running. Listening on :${AIP_PORT} (proxy) and :${LITELLM_PORT} (litellm)"

# ── Keep container alive, forward signals ─────────────────────────────────────
wait

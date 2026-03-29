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
    [ -n "$LITELLM_PIPE" ] && rm -f "$LITELLM_PIPE"
    wait
    echo "Done."
    exit 0
}
trap shutdown TERM INT

# ── Start LiteLLM ─────────────────────────────────────────────────────────────
echo "Starting LiteLLM on :${LITELLM_PORT}..."
# tee mirrors stdout to the terminal so the GitHub Copilot device-flow prompt
# ("Visit https://github.com/login/device/code and enter code XXXX-XXXX") is
# visible on first run, while still persisting all output to logs/litellm.log.
# A named pipe is used so $LITELLM_PID captures litellm, not tee.
mkdir -p logs
LITELLM_PIPE=$(mktemp -u /tmp/litellm.pipe.XXXXXX)
mkfifo "$LITELLM_PIPE"
tee -a logs/litellm.log < "$LITELLM_PIPE" &
litellm --config /app/copilot-config.yaml --port "$LITELLM_PORT" > "$LITELLM_PIPE" 2>&1 &
LITELLM_PID=$!

# ── Wait for LiteLLM to be ready (up to 120s) ────────────────────────────────
echo "Waiting for LiteLLM to be ready..."
i=0
while [ "$i" -lt 120 ]; do
    if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('localhost',$LITELLM_PORT))==0 else 1)" 2>/dev/null; then
        break
    fi
    sleep 1
    i=$((i+1))
done
if [ "$i" -ge 120 ]; then
    echo "ERROR: LiteLLM did not start within 120 seconds" >&2
    exit 1
fi
echo "  LiteLLM ready."

# ── Start aip-proxy ───────────────────────────────────────────────────────────
echo "Starting aip-proxy on :${AIP_PORT}..."
aip-proxy start --target "http://localhost:${LITELLM_PORT}" --port "$AIP_PORT" --host 0.0.0.0 >> logs/aip-proxy.log 2>&1 &
AIP_PID=$!

# ── Wait for aip-proxy to be ready (up to 60s) ───────────────────────────────
echo "Waiting for aip-proxy to be ready..."
i=0
while [ "$i" -lt 60 ]; do
    if python3 -c "import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('localhost',$AIP_PORT))==0 else 1)" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$AIP_PID" 2>/dev/null; then
        echo "ERROR: aip-proxy process died unexpectedly" >&2
        exit 1
    fi
    sleep 1
    i=$((i+1))
done
if [ "$i" -ge 60 ]; then
    echo "ERROR: aip-proxy did not start within 60 seconds" >&2
    exit 1
fi
echo "  aip-proxy ready."

echo "  Both services running. Listening on :${AIP_PORT} (proxy) and :${LITELLM_PORT} (litellm)"

# ── Keep container alive, forward signals ─────────────────────────────────────
wait

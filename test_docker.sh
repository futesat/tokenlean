#!/bin/sh
# test_docker.sh — Integration tests for the tokenlean Docker container
#
# Usage:
#   ./test_docker.sh          # build + run tests + teardown
#   ./test_docker.sh --no-build  # skip build (use existing image)
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -e

# ── Config ────────────────────────────────────────────────────────────────────
AIP_PORT=4444
LITELLM_PORT=4445
CONTAINER="tokenlean-test"
IMAGE="tokenlean:test"
COMPOSE_FILE="docker-compose.yml"
STARTUP_TIMEOUT=60   # seconds to wait for healthy state
NO_BUILD=0

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { printf "${GREEN}  ✓${RESET} %s\n" "$1"; }
fail() { printf "${RED}  ✗${RESET} %s\n" "$1"; FAILURES=$((FAILURES+1)); }
info() { printf "${YELLOW}  →${RESET} %s\n" "$1"; }
header() { printf "\n${BOLD}%s${RESET}\n" "$1"; }

FAILURES=0

# ── Parse args ────────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-build) NO_BUILD=1 ;;
    esac
done

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
    info "Tearing down test container..."
    docker compose -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# ── Prerequisites ─────────────────────────────────────────────────────────────
header "[ tokenlean docker tests ]"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker not found" >&2
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: docker compose plugin not found" >&2
    exit 1
fi

# ── Test 1: Build ─────────────────────────────────────────────────────────────
header "1. Image build"

if [ "$NO_BUILD" -eq 0 ]; then
    info "Building image..."
    if docker compose -f "$COMPOSE_FILE" build >/dev/null 2>&1; then
        pass "Image builds successfully"
    else
        fail "Image build failed"
        docker compose -f "$COMPOSE_FILE" build  # re-run to show error
        exit 1
    fi
else
    info "Skipping build (--no-build)"
fi

# ── Test 2: OCI labels present ────────────────────────────────────────────────
header "2. OCI labels"

LABEL=$(docker inspect tokenlean:latest --format '{{index .Config.Labels "org.opencontainers.image.title"}}' 2>/dev/null || echo "")
if [ "$LABEL" = "tokenlean" ]; then
    pass "OCI label org.opencontainers.image.title = tokenlean"
else
    fail "OCI label org.opencontainers.image.title missing or wrong (got: '$LABEL')"
fi

LABEL_SRC=$(docker inspect tokenlean:latest --format '{{index .Config.Labels "org.opencontainers.image.source"}}' 2>/dev/null || echo "")
if [ -n "$LABEL_SRC" ]; then
    pass "OCI label org.opencontainers.image.source present"
else
    fail "OCI label org.opencontainers.image.source missing"
fi

# ── Test 3: Ports exposed ─────────────────────────────────────────────────────
header "3. Exposed ports"

PORTS=$(docker inspect tokenlean:latest --format '{{json .Config.ExposedPorts}}' 2>/dev/null || echo "{}")
if echo "$PORTS" | grep -q "4444"; then
    pass "Port 4444 exposed"
else
    fail "Port 4444 not exposed in image"
fi

if echo "$PORTS" | grep -q "4445"; then
    pass "Port 4445 exposed"
else
    fail "Port 4445 not exposed in image"
fi

# ── Test 4: Container starts ──────────────────────────────────────────────────
header "4. Container startup"

info "Starting container..."
docker compose -f "$COMPOSE_FILE" up -d >/dev/null 2>&1
pass "Container started (docker compose up -d)"

# ── Test 5: Wait for healthy ──────────────────────────────────────────────────
header "5. Health check"

info "Waiting up to ${STARTUP_TIMEOUT}s for healthy state..."
i=0
HEALTHY=0
while [ "$i" -lt "$STARTUP_TIMEOUT" ]; do
    STATUS=$(docker inspect --format '{{.State.Health.Status}}' tokenlean 2>/dev/null || echo "unknown")
    if [ "$STATUS" = "healthy" ]; then
        HEALTHY=1
        break
    fi
    sleep 2
    i=$((i+2))
done

if [ "$HEALTHY" -eq 1 ]; then
    pass "Container reached healthy state in ${i}s"
else
    STATUS=$(docker inspect --format '{{.State.Health.Status}}' tokenlean 2>/dev/null || echo "unknown")
    fail "Container did not reach healthy state within ${STARTUP_TIMEOUT}s (status: $STATUS)"
    info "Last logs:"
    docker compose -f "$COMPOSE_FILE" logs --tail=30
fi

# ── Test 6: aip-proxy /health endpoint ───────────────────────────────────────
header "6. aip-proxy HTTP endpoints"

HTTP_STATUS=$(python3 -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://localhost:${AIP_PORT}/health', timeout=5)
    sys.exit(0 if r.status == 200 else 1)
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && echo "200" || echo "fail")

if [ "$HTTP_STATUS" = "200" ]; then
    pass "GET :${AIP_PORT}/health → 200 OK"
else
    fail "GET :${AIP_PORT}/health did not return 200"
fi

# ── Test 7: LiteLLM /health endpoint ─────────────────────────────────────────
header "7. LiteLLM HTTP endpoints"

LITELLM_STATUS=$(python3 -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://localhost:${LITELLM_PORT}/health', timeout=5)
    sys.exit(0 if r.status == 200 else 1)
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null && echo "200" || echo "fail")

if [ "$LITELLM_STATUS" = "200" ]; then
    pass "GET :${LITELLM_PORT}/health → 200 OK"
else
    fail "GET :${LITELLM_PORT}/health did not return 200"
fi

# ── Test 8: OpenAI-compatible /v1/models endpoint ────────────────────────────
header "8. OpenAI API compatibility"

MODELS=$(python3 -c "
import urllib.request, json, sys
try:
    req = urllib.request.Request('http://localhost:${AIP_PORT}/v1/models',
          headers={'Authorization': 'Bearer litellm'})
    r = urllib.request.urlopen(req, timeout=5)
    data = json.loads(r.read())
    models = [m['id'] for m in data.get('data', [])]
    print(' '.join(models))
    sys.exit(0)
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null || echo "")

if [ -n "$MODELS" ]; then
    pass "GET :${AIP_PORT}/v1/models returned model list"
    info "Models: $(echo "$MODELS" | tr ' ' '\n' | head -5 | tr '\n' ' ')..."
else
    fail "GET :${AIP_PORT}/v1/models failed or returned empty list"
fi

# ── Test 9: Container restarts cleanly ───────────────────────────────────────
header "9. Graceful restart"

info "Restarting container..."
docker compose -f "$COMPOSE_FILE" restart tokenlean >/dev/null 2>&1
sleep 5

STATE=$(docker inspect --format '{{.State.Status}}' tokenlean 2>/dev/null || echo "unknown")
if [ "$STATE" = "running" ]; then
    pass "Container still running after restart"
else
    fail "Container not running after restart (state: $STATE)"
fi

# ── Test 10: copilot-config.yaml is read-only volume ─────────────────────────
header "10. Volume mount"

MOUNT=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/copilot-config.yaml"}}{{.Mode}}{{end}}{{end}}' tokenlean 2>/dev/null || echo "")
if [ "$MOUNT" = "ro" ]; then
    pass "copilot-config.yaml mounted as read-only"
else
    fail "copilot-config.yaml not mounted read-only (mode: '$MOUNT')"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}────────────────────────────────────────${RESET}\n"
if [ "$FAILURES" -eq 0 ]; then
    printf "${GREEN}${BOLD}  All tests passed.${RESET}\n\n"
    exit 0
else
    printf "${RED}${BOLD}  $FAILURES test(s) failed.${RESET}\n\n"
    exit 1
fi

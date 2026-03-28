#!/bin/sh
# test_docker.sh — Integration tests for the tokenlean Docker container
#
# Usage:
#   ./test_docker.sh                   # build + structural + functional tests + teardown
#   ./test_docker.sh --no-build        # skip build
#   ./test_docker.sh --structural-only # only run tests that don't need Copilot credentials (CI mode)
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -e

# ── Config ────────────────────────────────────────────────────────────────────
AIP_PORT=4444
LITELLM_PORT=4445
STARTUP_TIMEOUT=90   # seconds to wait for healthy state
NO_BUILD=0
STRUCTURAL_ONLY=0

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

pass() { printf "${GREEN}  ✓${RESET} %s\n" "$1"; }
fail() { printf "${RED}  ✗${RESET} %s\n" "$1"; FAILURES=$((FAILURES+1)); }
skip() { printf "${YELLOW}  ⊘${RESET} %s ${YELLOW}(skipped — requires Copilot credentials)${RESET}\n" "$1"; }
info() { printf "${YELLOW}  →${RESET} %s\n" "$1"; }
header() { printf "\n${BOLD}%s${RESET}\n" "$1"; }

FAILURES=0

# ── Parse args ────────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --no-build)        NO_BUILD=1 ;;
        --structural-only) STRUCTURAL_ONLY=1 ;;
    esac
done

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
    info "Tearing down test container..."
    docker compose down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# ── Prerequisites ─────────────────────────────────────────────────────────────
header "[ tokenlean docker tests ]"
[ "$STRUCTURAL_ONLY" -eq 1 ] && info "Mode: structural only (no Copilot credentials required)"

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
    if docker compose build >/dev/null 2>&1; then
        pass "Image builds successfully"
    else
        fail "Image build failed"
        docker compose build
        exit 1
    fi
else
    info "Skipping build (--no-build)"
fi

# ── Test 2: OCI labels ────────────────────────────────────────────────────────
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

# ── Test 4: Entrypoint present and executable ─────────────────────────────────
header "4. Entrypoint"

EP=$(docker inspect tokenlean:latest --format '{{json .Config.Entrypoint}}' 2>/dev/null || echo "")
if echo "$EP" | grep -q "entrypoint.sh"; then
    pass "Entrypoint set to entrypoint.sh"
else
    fail "Entrypoint not set correctly (got: '$EP')"
fi

# Check entrypoint is executable inside the image
if docker run --rm --entrypoint sh tokenlean:latest -c "test -x /app/entrypoint.sh" 2>/dev/null; then
    pass "entrypoint.sh is executable inside image"
else
    fail "entrypoint.sh is not executable inside image"
fi

# ── Test 5: venv present inside image ────────────────────────────────────────
header "5. Virtual environment"

if docker run --rm --entrypoint sh tokenlean:latest -c "test -f /app/.venv/bin/litellm" 2>/dev/null; then
    pass "litellm binary present in /app/.venv"
else
    fail "litellm binary not found in /app/.venv"
fi

if docker run --rm --entrypoint sh tokenlean:latest -c "test -f /app/.venv/bin/aip-proxy" 2>/dev/null; then
    pass "aip-proxy binary present in /app/.venv"
else
    fail "aip-proxy binary not found in /app/.venv"
fi

# ── Test 6: Container starts ──────────────────────────────────────────────────
header "6. Container startup"

info "Starting container..."
docker compose up -d >/dev/null 2>&1
pass "Container started (docker compose up -d)"

# ── Test 7: Volume mount ──────────────────────────────────────────────────────
header "7. Volume mount"

MOUNT=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/copilot-config.yaml"}}{{.Mode}}{{end}}{{end}}' tokenlean 2>/dev/null || echo "")
if [ "$MOUNT" = "ro" ]; then
    pass "copilot-config.yaml mounted as read-only"
else
    fail "copilot-config.yaml not mounted read-only (mode: '$MOUNT')"
fi

# ── Test 8: Graceful restart ──────────────────────────────────────────────────
header "8. Graceful restart"

info "Restarting container..."
docker compose restart tokenlean >/dev/null 2>&1
sleep 3
STATE=$(docker inspect --format '{{.State.Status}}' tokenlean 2>/dev/null || echo "unknown")
if [ "$STATE" = "running" ]; then
    pass "Container still running after restart"
else
    fail "Container not running after restart (state: $STATE)"
fi

# ── Functional tests (require Copilot credentials) ────────────────────────────

if [ "$STRUCTURAL_ONLY" -eq 1 ]; then
    header "9–11. Functional tests"
    skip "Health check (aip-proxy)"
    skip "Health check (LiteLLM)"
    skip "OpenAI /v1/models endpoint"
else
    # ── Test 9: Wait for healthy ───────────────────────────────────────────────
    header "9. Health check"

    info "Waiting up to ${STARTUP_TIMEOUT}s for healthy state..."
    i=0; HEALTHY=0
    while [ "$i" -lt "$STARTUP_TIMEOUT" ]; do
        STATUS=$(docker inspect --format '{{.State.Health.Status}}' tokenlean 2>/dev/null || echo "unknown")
        [ "$STATUS" = "healthy" ] && HEALTHY=1 && break
        sleep 2; i=$((i+2))
    done

    if [ "$HEALTHY" -eq 1 ]; then
        pass "Container reached healthy state in ${i}s"
    else
        STATUS=$(docker inspect --format '{{.State.Health.Status}}' tokenlean 2>/dev/null || echo "unknown")
        fail "Container not healthy after ${STARTUP_TIMEOUT}s (status: $STATUS)"
        info "Last logs:"; docker compose logs --tail=30
    fi

    # ── Test 10: aip-proxy /health ────────────────────────────────────────────
    header "10. aip-proxy HTTP"

    HTTP_STATUS=$(python3 -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://localhost:${AIP_PORT}/health', timeout=5)
    sys.exit(0 if r.status == 200 else 1)
except Exception as e:
    print(e, file=sys.stderr); sys.exit(1)
" 2>/dev/null && echo "200" || echo "fail")

    if [ "$HTTP_STATUS" = "200" ]; then
        pass "GET :${AIP_PORT}/health → 200 OK"
    else
        fail "GET :${AIP_PORT}/health did not return 200"
    fi

    # ── Test 11: /v1/models ───────────────────────────────────────────────────
    header "11. OpenAI API compatibility"

    MODELS=$(python3 -c "
import urllib.request, json, sys
try:
    req = urllib.request.Request('http://localhost:${AIP_PORT}/v1/models',
          headers={'Authorization': 'Bearer litellm'})
    r = urllib.request.urlopen(req, timeout=5)
    data = json.loads(r.read())
    print(' '.join(m['id'] for m in data.get('data', [])))
    sys.exit(0)
except Exception as e:
    print(e, file=sys.stderr); sys.exit(1)
" 2>/dev/null || echo "")

    if [ -n "$MODELS" ]; then
        pass "GET :${AIP_PORT}/v1/models returned model list"
        info "Models: $(echo "$MODELS" | tr ' ' '\n' | head -5 | tr '\n' ' ')..."
    else
        fail "GET :${AIP_PORT}/v1/models failed or returned empty"
    fi
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

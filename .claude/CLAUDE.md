# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

**tokenlean** chains two token-reduction proxies in front of the GitHub Copilot API:

```
Your tool (OpenAI-compatible client)
      │ :4444
  aip-proxy        ← input prompt compression (15-40%)
      │ :4445
   LiteLLM          ← OpenAI API → GitHub Copilot API translation
      │
 GitHub Copilot API
```

A third layer, **rtk**, compresses shell command *outputs* before they enter Claude's context (60-90%).

## Key files

| File | Purpose |
|---|---|
| `Dockerfile` | Multi-stage OCI image (builder + runtime, python:3.11-slim) |
| `docker-compose.yml` | One-command container deployment, mounts copilot-config.yaml as volume |
| `.dockerignore` | Excludes .venv, logs, .git, .claude, .devcontainer, .github, test_docker.sh |
| `entrypoint.sh` | Container entrypoint: starts LiteLLM, waits for readiness, starts aip-proxy, traps SIGTERM |
| `test_docker.sh` | Docker integration test suite (10 tests); `--no-build` flag to skip rebuild |
| `.devcontainer/devcontainer.json` | Dev container config for VS Code / GitHub Codespaces (reuses docker-compose.yml) |
| `.github/workflows/docker-tests.yml` | CI: builds image and runs test_docker.sh on push/PR to main or develop |
| `copilot-config.yaml` | LiteLLM model list (with `reasoning_effort` per model) — add/remove models here |
| `configure_claude.py` | Patches `~/.claude/settings.json` to point Claude at the proxy; `apply` / `restore` subcommands |
| `Makefile` | All automation — cross-platform (macOS + Linux) |
| `pyproject.toml` | Poetry configuration and dependencies (`litellm[proxy]`, `aip-proxy`, etc.) |
| `savings.py` | Live token savings dashboard script |

## Deployment options

### Option A — Dev Container (VS Code / Codespaces)

Reuses `docker-compose.yml`. Container stays alive for development; proxies are started manually.

```bash
# Inside the container:
/app/entrypoint.sh   # start both proxies
```

### Option B — Docker

```bash
docker compose up -d --build      # build image and start in background
docker compose ps                  # check status / health
docker compose logs -f             # tail logs
docker compose down                # stop and remove container
docker compose restart tokenlean   # reload after editing copilot-config.yaml
```

- `copilot-config.yaml` is mounted as read-only volume — model changes don't require a rebuild
- Logs are persisted to `litellm.log` and `aip-proxy.log` in the project directory
- Container health checked via `GET http://localhost:4444/health` every 15s

### Option C — Bare metal (macOS + Linux)

```bash
make                  # Show all available targets (default)
make install          # Full setup: venv + Claude Code + rtk + configure + start proxies
make venv             # Install Poetry and dependencies (idempotent — only runs when pyproject.toml or poetry.lock change)
make start            # Start LiteLLM (:4445) and aip-proxy (:4444) in background (waits for LiteLLM readiness)
make stop             # Graceful stop (SIGTERM → 3s grace → kill -9 fallback)
make restart          # Stop then start
make status           # Show RUNNING / STOPPED / DEAD state for each service
make log-aip          # Tail aip-proxy.log
make log-litellm      # Tail litellm.log
make savings          # Live token savings dashboard — aip-proxy + rtk (Ctrl+C to exit)
make configure-claude # Patch ~/.claude/settings.json (timestamped backup created)
make unconfigure-claude # Restore last settings backup
make install-claude   # Install Claude Code CLI via npm (if not already installed)
make install-rtk      # Install rtk via brew or curl fallback + configure Claude Code hook
make clean-logs       # Delete log files
make clean            # Stop services + delete logs, PIDs, and virtualenv
```

`configure_claude.py` can also be called directly:

```bash
python3 configure_claude.py apply    # point Claude at the proxy
python3 configure_claude.py restore  # roll back to last backup
```

## CI

GitHub Actions workflow at `.github/workflows/docker-tests.yml`:
- Triggers on push/PR to `main` or `develop`
- Only runs when Docker-related files change (Dockerfile, docker-compose.yml, entrypoint.sh, copilot-config.yaml, pyproject.toml, poetry.lock, test_docker.sh)
- Builds image with BuildKit + layer cache, then runs `test_docker.sh --no-build`
- On failure: prints last 100 lines of container logs

## Architecture notes

- **aip-proxy** runs on `:4444` and forwards to LiteLLM on `:4445`. All external clients hit `:4444`.
- **LiteLLM** is configured entirely via `copilot-config.yaml`. Adding a new Copilot model only requires a new entry there (no Python changes).
- Every `github_copilot/*` model requires `Editor-Version` and `Copilot-Integration-Id` headers — these are set per-model in `copilot-config.yaml`.
- OpenAI reasoning models (GPT-5.x) have `reasoning_effort` set in `copilot-config.yaml` (`high` or `xhigh`).
- `configure_claude.py` sets four env vars in `~/.claude/settings.json` (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`). All other settings in the file are preserved.
- Backups of `settings.json` are named `settings.json.<YYYYMMDD_HHMMSS>.bak`; `restore` picks the lexicographically last one.
- Processes are tracked via `litellm.pid` / `aip-proxy.pid` (written by `make start`, used by `make stop`).
- The venv sentinel (`.venv/.installed`) makes `make venv` idempotent — `poetry install` only re-runs when `pyproject.toml` changes.

## Cross-platform compatibility (macOS + Linux)

- Port killing: `lsof` → `fuser` fallback
- Port wait: `nc -z` → `python3 socket` fallback
- All shell commands use POSIX `>/dev/null 2>&1` (not bash-only `&>/dev/null`)
- `stop` does not depend on `venv` — can kill processes without installing dependencies
- Claude Code install uses `npm` (the only cross-platform method)
- rtk install uses `brew` with `curl` install script as fallback for Linux without Homebrew

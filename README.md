# tokenlean

[![Docker Tests](https://github.com/futesat/tokenlean/actions/workflows/docker-tests.yml/badge.svg)](https://github.com/futesat/tokenlean/actions/workflows/docker-tests.yml)

**tokenlean** is a lightweight local proxy setup that enables [Claude Code](https://docs.anthropic.com/en/docs/agents-and-tools/claude-code) to use GitHub Copilot models (GPT-4.1, Claude Sonnet/Opus, Gemini, Grok, and more) as a standard OpenAI-compatible API endpoint. It also integrates [rtk](https://github.com/rtk-ai/rtk) as a Claude Code hook to compress command outputs, delivering a massive reduction in token consumption. It chains [aip-proxy](https://pypi.org/project/aip-proxy/) (prompt compression) and [LiteLLM](https://github.com/BerriAI/litellm) (Copilot API translation) so that Claude Code or any OpenAI-compatible tool can use your GitHub Copilot subscription as the backend with reduced token consumption.

> **Double savings** — tokenlean gives you two independent layers of token reduction:
> 1. **[rtk](https://github.com/rtk-ai/rtk)**: compresses shell command *outputs* by 60–90% before they reach the model context.
> 2. **[aip-proxy](https://pypi.org/project/aip-proxy/)**: compresses the *input prompts* sent to the LLM (whitespace, comments, deduplication) for an additional 15–40% reduction.

## How it works

```
Your app / tool
      │
      ▼ HTTP :4444
  aip-proxy          ← compresses prompts 15-40% (whitespace, comments, deduplication)
      │
      ▼ HTTP :4445
   LiteLLM            ← translates OpenAI API calls to GitHub Copilot API
      │
      ▼ HTTPS
 GitHub Copilot API
```

## Available models

All models configured in `copilot-config.yaml`. Use the `model_name` value as the `model` field in your API calls.

### OpenAI

| Model name           | Underlying model    | Reasoning effort |
| -------------------- | ------------------- | ---------------- |
| `gpt-4-1`           | GPT-4.1             | —                |
| `gpt-4o`            | GPT-4o              | —                |
| `gpt-5-mini`        | GPT-5 mini          | high             |
| `gpt-5-1`           | GPT-5.1             | high             |
| `gpt-5-1-codex`     | GPT-5.1 Codex       | high             |
| `gpt-5-1-codex-max` | GPT-5.1 Codex Max   | xhigh            |
| `gpt-5-1-codex-mini`| GPT-5.1 Codex mini  | high             |
| `gpt-5-2`           | GPT-5.2             | xhigh            |
| `gpt-5-2-codex`     | GPT-5.2 Codex       | xhigh            |
| `gpt-5-3-codex`     | GPT-5.3 Codex       | xhigh            |
| `gpt-5-4`           | GPT-5.4             | xhigh            |
| `gpt-5-4-mini`      | GPT-5.4 mini        | high             |

### Anthropic

| Model name          | Underlying model  |
| ------------------- | ----------------- |
| `claude-haiku-4-5`  | Claude Haiku 4.5  |
| `claude-sonnet-4`   | Claude Sonnet 4   |
| `claude-sonnet-4-5` | Claude Sonnet 4.5 |
| `claude-sonnet-4-6` | Claude Sonnet 4.6 |
| `claude-opus-4-5`   | Claude Opus 4.5   |
| `claude-opus-4-6`   | Claude Opus 4.6   |

### Google

| Model name       | Underlying model           |
| ---------------- | -------------------------- |
| `gemini-2-5-pro` | Gemini 2.5 Pro             |
| `gemini-3-flash` | Gemini 3 Flash *(preview)* |
| `gemini-3-1-pro` | Gemini 3.1 Pro *(preview)* |

### xAI

| Model name         | Underlying model |
| ------------------ | ---------------- |
| `grok-code-fast-1` | Grok Code Fast 1 |

## Requirements

**Docker (Option A):**
- Docker with Compose plugin

**Bare metal (Option B):**
- Python 3.11+
- Node.js / npm (for Claude Code CLI install)
- Poetry (installed automatically via `make venv`)
- A valid GitHub Copilot subscription and a logged-in VS Code session (or GitHub CLI auth)
- [rtk](https://github.com/rtk-ai/rtk) (installed automatically via `make install`)

**Supported platforms:** macOS and Linux.

## Setup & Usage

### Option A — Dev Container (VS Code / Codespaces)

The repo includes a dev container that reutilizes the existing `docker-compose.yml` — gives you a full Python 3.11 environment with all dependencies pre-installed, Claude Code CLI, and ports 4444/4445 forwarded automatically.

**Open in VS Code:**
1. Install the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
2. `Ctrl+Shift+P` → **Dev Containers: Reopen in Container**

**Open in GitHub Codespaces:**

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/futesat/tokenlean)

Once inside the container, start the proxies manually:
```bash
/app/entrypoint.sh
```

---

### Option B — Docker (recommended for production use)

Run the full proxy stack in a container without installing Python, Poetry, or any dependencies locally.

**Requirements:** Docker with Compose plugin (or `docker-compose` v2).

```bash
# Build and start (detached)
docker compose up -d --build

# Check status / health
docker compose ps

# Tail logs
docker compose logs -f

# Stop
docker compose down
```

The container exposes:
- `:4444` — aip-proxy (connect your OpenAI-compatible client here)
- `:4445` — LiteLLM (internal, exposed for debugging)

`copilot-config.yaml` is mounted as a read-only volume — you can edit models and `docker compose restart tokenlean` without rebuilding the image.

Logs are persisted to `litellm.log` and `aip-proxy.log` in the project directory.

> [!NOTE]
> The container uses a `HEALTHCHECK` on `http://localhost:4444/health`. Wait for it to show `healthy` before sending requests.

---

### Option B — Bare metal (native)

### 1. Full one-shot setup

```bash
make install
```

This runs the complete setup in sequence:
1. **`venv`** — installs Poetry and project dependencies
2. **`install-claude`** — installs Claude Code CLI via npm (if not already installed)
3. **`install-rtk`** — installs [rtk](https://github.com/rtk-ai/rtk) via Homebrew (or the official install script as fallback on Linux) and configures the Claude Code hook
4. **`configure-claude`** — patches `~/.claude/settings.json` to point at the local proxy (timestamped backup saved)
5. **`start`** — starts LiteLLM and aip-proxy in background

After running `make install`, restart Claude Code to activate the rtk hook.

### 2. Install dependencies only

```bash
make venv
```

Ensures Poetry is installed and runs `poetry install`. This is **idempotent** — it only re-runs when `pyproject.toml` or `poetry.lock` change. Runs automatically as a dependency of `make start`.

### 3. Start the proxies

```bash
make start
```

Starts LiteLLM (port `4445`) first, **waits for it to be ready** (up to 15 seconds), then starts aip-proxy (port `4444`). Both run in the background. Logs are written to `litellm.log` and `aip-proxy.log`.

> [!WARNING]
> Running `make start` will automatically stop any existing processes running on ports `4444` and `4445`.

### 4. Use the API

Point any OpenAI-compatible client to `http://localhost:4444` and use one of the model names above.

```bash
curl http://localhost:4444/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4-1",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### 5. Stop the proxies

```bash
make stop
```

Sends SIGTERM first, waits 3 seconds for graceful shutdown, then kills any remaining processes on the ports as a fallback.

### 6. Check service status

```bash
make status
```

Shows RUNNING / STOPPED / DEAD (stale PID) state for each service.

### All commands

| Command                   | Description                                                                         |
| ------------------------- | ----------------------------------------------------------------------------------- |
| `make`                    | Show all available targets (default)                                                |
| `make install`            | Full setup: venv + Claude Code + rtk + configure + start                            |
| `make install-claude`     | Install Claude Code CLI via npm                                                     |
| `make install-rtk`        | Install rtk and configure its Claude Code hook                                      |
| `make configure-claude`   | Patch `~/.claude/settings.json` to use the local proxy (timestamped backup created) |
| `make unconfigure-claude` | Restore the most recent settings backup                                             |
| `make venv`               | Install Poetry and dependencies (idempotent)                                        |
| `make start`              | Start LiteLLM + aip-proxy in background (waits for readiness)                       |
| `make stop`               | Graceful stop (SIGTERM → 3s → kill -9 fallback)                                     |
| `make restart`            | Stop then start                                                                     |
| `make status`             | Show running/stopped state for each service                                         |
| `make log-aip`            | Tail the aip-proxy log                                                              |
| `make log-litellm`        | Tail the LiteLLM log                                                                |
| `make savings`            | Live token savings dashboard — aip-proxy + rtk (Ctrl+C to exit)                     |
| `make clean-logs`         | Delete log files                                                                    |
| `make clean`              | Stop services + delete logs, PIDs, and virtualenv                                   |

## Claude Code integration

`make configure-claude` (or `make install`) patches `~/.claude/settings.json` with:

```json
"env": {
  "ANTHROPIC_AUTH_TOKEN": "litellm",
  "ANTHROPIC_BASE_URL": "http://localhost:4444",
  "ANTHROPIC_MODEL": "claude-sonnet-4-6",
  "ANTHROPIC_SMALL_FAST_MODEL": "gpt-4-1"
}
```

All other settings (hooks, model, etc.) are preserved. A timestamped backup is saved alongside the original (e.g. `settings.json.20260327_143012.bak`) before every modification. Run `make unconfigure-claude` to roll back to the last backup.

The configuration script lives in `configure_claude.py` and can also be called directly:

```bash
python3 configure_claude.py apply    # point Claude at the proxy
python3 configure_claude.py restore  # roll back to last backup
```

## rtk integration — the second layer of savings

[rtk](https://github.com/rtk-ai/rtk) is a Rust CLI proxy that reduces LLM token consumption by 60–90% by filtering and compressing command outputs before they reach the model context. When combined with tokenlean it delivers **two independent layers of savings**:

```
Without tokenlean + rtk:          With tokenlean + rtk:

 Claude ──────────────► OpenAI    Claude ──────────────► aip-proxy ──► LiteLLM ──► Copilot API
  Pay per token ($$$$)              Flat Copilot subscription ($)
  Raw command output                rtk compresses outputs 60-90%
                                    → fewer premium requests consumed
```

| Saving layer  | What it compresses                                       | Reduction |
| ------------- | -------------------------------------------------------- | --------- |
| **rtk**       | Shell command *outputs* (git, cargo, ls, grep…)          | 60–90%    |
| **aip-proxy** | Input *prompts* (whitespace, comments, duplicate blocks) | 15–40%    |

`make install-rtk` installs rtk and runs `rtk init -g --auto-patch`, which installs a `PreToolUse` hook into Claude Code that transparently rewrites common shell commands (`git status`, `cargo test`, `ls`, etc.) to their rtk-filtered equivalents — with zero token overhead and no changes to your workflow.

After running `make install`, restart Claude Code to activate the hook.

> **Tip**: run `rtk gain` at any time to see how many tokens (and premium requests) rtk has saved in your sessions.

## Cross-platform compatibility

The Makefile is fully compatible with **macOS** and **Linux**:

- Port killing uses `lsof` with `fuser` as fallback (for minimal Linux distros)
- Port readiness check uses `nc -z` with `python3 socket` as fallback (for distros with `ncat`)
- All shell commands use POSIX-compatible syntax (`>/dev/null 2>&1`, not `&>/dev/null`)
- `make stop` does not depend on `venv` — can stop services without installing dependencies
- Claude Code is installed via `npm` (the universal cross-platform method)
- rtk is installed via Homebrew with `curl` install script as fallback for Linux without Homebrew

## Project structure

```
tokenlean/
├── .devcontainer/
│   └── devcontainer.json  # VS Code / GitHub Codespaces dev container
├── .github/
│   └── workflows/
│       └── docker-tests.yml  # CI: build + integration tests
├── Dockerfile             # Multi-stage OCI image (builder + runtime)
├── docker-compose.yml     # One-command container deployment
├── .dockerignore          # Excludes .venv, logs, .git, etc.
├── entrypoint.sh          # Container entrypoint (starts both services, handles SIGTERM)
├── test_docker.sh         # Docker integration test suite
├── copilot-config.yaml    # LiteLLM model definitions for GitHub Copilot
├── configure_claude.py    # Script to patch ~/.claude/settings.json
├── savings.py             # Live token savings dashboard
├── Makefile               # Cross-platform automation (macOS + Linux)
├── pyproject.toml         # Poetry configuration and dependencies
├── poetry.lock            # Poetry lock file (version control)
├── .claude/CLAUDE.md      # Claude Code project instructions
├── litellm.log            # LiteLLM runtime log (generated)
├── aip-proxy.log          # aip-proxy runtime log (generated)
├── litellm.pid            # LiteLLM process ID (generated, bare-metal only)
├── aip-proxy.pid          # aip-proxy process ID (generated, bare-metal only)
└── .venv/                 # Python virtual environment (generated, bare-metal only)
```

## Acknowledgements

This project would not be possible without the following open-source projects:

- **[LiteLLM](https://github.com/BerriAI/litellm)** — The backbone of this setup. LiteLLM provides a unified OpenAI-compatible proxy that translates API calls across dozens of LLM providers. Huge thanks to the BerriAI team for building and maintaining it.

- **[aip-proxy](https://pypi.org/project/aip-proxy/)** — Token compression proxy that sits between your tool and the LLM API. Compresses input prompts via whitespace normalization, code comment removal, block deduplication, and pattern abbreviation — reducing input token consumption by 15–40% without losing semantic content.

- **[FastAPI](https://github.com/tiangolo/fastapi)** & **[Uvicorn](https://github.com/encode/uvicorn)** — High-performance async web framework and ASGI server that power both proxy layers.

- **[httpx](https://github.com/encode/httpx)** — Modern async HTTP client used internally for proxying requests.

- **[rtk](https://github.com/rtk-ai/rtk)** — Rust Token Killer. A high-performance CLI proxy that reduces LLM token consumption by 60–90% by filtering and compressing the output of common dev commands. Single binary, zero dependencies.

## Maintainers

Maintained by [@gdilo](https://github.com/gdilo) and [@futesat](https://github.com/futesat).

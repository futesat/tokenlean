# tokenlean

**tokenlean** is a lightweight local proxy setup that exposes GitHub Copilot models (GPT-4.1, Claude Sonnet/Opus, Gemini) as a standard OpenAI-compatible API endpoint. It bridges [LiteLLM](https://github.com/BerriAI/litellm) and [aip-proxy](https://pypi.org/project/aip-proxy/) so that any tool or application that speaks the OpenAI API can use your GitHub Copilot subscription as the backend.

## How it works

```
Your app / tool
      │
      ▼ HTTP :4444
  aip-proxy          ← handles auth injection (GitHub Copilot token)
      │
      ▼ HTTP :4445
   LiteLLM            ← translates OpenAI API calls to Copilot model API
      │
      ▼ HTTPS
 GitHub Copilot API
```

## Available models

Configured in `copilot-config.yaml`:

| Model name | Underlying model |
|---|---|
| `gpt-4-1` | GitHub Copilot / GPT-4.1 |
| `claude-sonnet-4-6` | GitHub Copilot / Claude Sonnet 4.6 |
| `claude-opus-4-6` | GitHub Copilot / Claude Opus 4.6 |
| `gemini-3-1-pro` | GitHub Copilot / Gemini 3.1 Pro |

## Requirements

- Python 3.11+
- A valid GitHub Copilot subscription and a logged-in VS Code session (or GitHub CLI auth)
- [rtk](https://github.com/rtk-ai/rtk) (installed automatically via `make install`)

## Setup & Usage

### 1. Full one-shot setup

```bash
make install
```

This runs `make install-rtk` and `make configure-claude` in sequence — installs [rtk](https://github.com/rtk-ai/rtk) via Homebrew (or the official install script as fallback), configures the Claude Code hook, and patches `~/.claude/settings.json` to point at the local proxy. A timestamped backup of your settings is always saved before any change.

### 2. Create the virtual environment and install dependencies

```bash
make venv
```

This creates a `venv/` folder and installs all packages from `requirements.txt`. Runs automatically as a dependency of `make start`.

### 3. Start the proxies

```bash
make start
```

Both LiteLLM (port `4445`) and aip-proxy (port `4444`) will start in the background. Logs are written to `litellm.log` and `aip-proxy.log`.

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

### All commands

| Command | Description |
|---|---|
| `make install` | Full setup: install rtk + configure Claude |
| `make install-rtk` | Install rtk and configure its Claude Code hook |
| `make configure-claude` | Patch `~/.claude/settings.json` to use the local proxy (timestamped backup created) |
| `make unconfigure-claude` | Restore the most recent settings backup |
| `make venv` | Create virtualenv and install dependencies |
| `make start` | Start LiteLLM + aip-proxy in background |
| `make stop` | Stop all proxy processes |
| `make log-aip` | Tail the aip-proxy log |
| `make log-litellm` | Tail the LiteLLM log |
| `make clean-logs` | Delete all log files |

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

## rtk integration

[rtk](https://github.com/rtk-ai/rtk) is a Rust CLI proxy that reduces LLM token consumption by 60–90% by filtering and compressing command outputs before they reach the model context.

`make install-rtk` installs rtk and runs `rtk init -g --auto-patch`, which installs a `PreToolUse` hook into Claude Code that transparently rewrites common shell commands (`git status`, `cargo test`, `ls`, etc.) to their rtk-filtered equivalents — with zero token overhead and no changes to your workflow.

After running `make install`, restart Claude Code to activate the hook.

## Project structure

```
tokenlean/
├── copilot-config.yaml    # LiteLLM model definitions for GitHub Copilot
├── configure_claude.py    # Script to patch ~/.claude/settings.json
├── Makefile               # Automation commands
├── requirements.txt       # Python dependencies
├── litellm.log            # LiteLLM runtime log (generated)
├── aip-proxy.log          # aip-proxy runtime log (generated)
└── venv/                  # Python virtual environment (generated)
```

## Acknowledgements

This project would not be possible without the following open-source projects:

- **[LiteLLM](https://github.com/BerriAI/litellm)** — The backbone of this setup. LiteLLM provides a unified OpenAI-compatible proxy that translates API calls across dozens of LLM providers. Huge thanks to the BerriAI team for building and maintaining it.

- **[aip-proxy](https://pypi.org/project/aip-proxy/)** — Handles GitHub Copilot authentication injection, making it transparent to forward requests through the Copilot API without manual token management.

- **[FastAPI](https://github.com/tiangolo/fastapi)** & **[Uvicorn](https://github.com/encode/uvicorn)** — High-performance async web framework and ASGI server that power both proxy layers.

- **[httpx](https://github.com/encode/httpx)** — Modern async HTTP client used internally for proxying requests.

- **[rtk](https://github.com/rtk-ai/rtk)** — Rust Token Killer. A high-performance CLI proxy that reduces LLM token consumption by 60–90% by filtering and compressing the output of common dev commands. Single binary, zero dependencies.

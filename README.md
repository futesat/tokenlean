# tokenlean

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

| Model name      | Underlying model |
| --------------- | ---------------- |
| `gpt-4-1`       | GPT-4.1          |
| `gpt-5-mini`    | GPT-5 mini       |
| `gpt-5-2`       | GPT-5.2          |
| `gpt-5-2-codex` | GPT-5.2 Codex    |
| `gpt-5-3-codex` | GPT-5.3 Codex    |
| `gpt-5-4`       | GPT-5.4          |
| `gpt-5-4-mini`  | GPT-5.4 mini     |

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

### Fine-tuned / Preview

| Model name    | Underlying model                     |
| ------------- | ------------------------------------ |
| `raptor-mini` | Raptor mini (fine-tuned GPT-5 mini)  |
| `goldeneye`   | Goldeneye (fine-tuned GPT-5.1-Codex) |

## Requirements

- Python 3.11+
- Poetry (installed automatically via `make venv`)
- A valid GitHub Copilot subscription and a logged-in VS Code session (or GitHub CLI auth)
- [rtk](https://github.com/rtk-ai/rtk) (installed automatically via `make install`)

## Setup & Usage

### 1. Full one-shot setup

```bash
make install
```

This runs `make install-rtk` and `make configure-claude` in sequence — installs [rtk](https://github.com/rtk-ai/rtk) via Homebrew (or the official install script as fallback), configures the Claude Code hook, and patches `~/.claude/settings.json` to point at the local proxy. A timestamped backup of your settings is always saved before any change.

### 2. Install dependencies with Poetry

```bash
make venv
```

This ensures Poetry is installed and runs `poetry install` to set up the environment. Runs automatically as a dependency of `make start`.

### 3. Start the proxies

```bash
make start
```

Both LiteLLM (port `4445`) and aip-proxy (port `4444`) will start in the background. Logs are written to `litellm.log` and `aip-proxy.log`.

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

> [!WARNING]
> Running `make stop` will automatically stop any existing processes running on ports `4444` and `4445`.

### All commands

| Command                   | Description                                                                         |
| ------------------------- | ----------------------------------------------------------------------------------- |
| `make install`            | Full setup: install rtk + configure Claude                                          |
| `make install-rtk`        | Install rtk and configure its Claude Code hook                                      |
| `make configure-claude`   | Patch `~/.claude/settings.json` to use the local proxy (timestamped backup created) |
| `make unconfigure-claude` | Restore the most recent settings backup                                             |
| `make venv`               | Install Poetry and dependencies via `poetry install`                                |
| `make start`              | Start LiteLLM + aip-proxy in background                                             |
| `make stop`               | Stop all proxy processes                                                            |
| `make log-aip`            | Tail the aip-proxy log                                                              |
| `make log-litellm`        | Tail the LiteLLM log                                                                |
| `make savings`            | Live token savings dashboard — aip-proxy + rtk (refreshes every 2s, Ctrl+C to exit) |
| `make clean-logs`         | Delete all log files                                                                |

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

## Project structure

```
tokenlean/
├── copilot-config.yaml    # LiteLLM model definitions for GitHub Copilot
├── configure_claude.py    # Script to patch ~/.claude/settings.json
├── Makefile               # Automation commands
├── pyproject.toml         # Poetry configuration and dependencies
├── poetry.lock            # Poetry lock file (version control)
├── litellm.log            # LiteLLM runtime log (generated)
├── aip-proxy.log          # aip-proxy runtime log (generated)
└── .venv/                 # Python virtual environment (generated)
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

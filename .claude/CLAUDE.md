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
| `copilot-config.yaml` | LiteLLM model list — add/remove models here |
| `configure_claude.py` | Patches `~/.claude/settings.json` to point Claude at the proxy; `apply` / `restore` subcommands |
| `Makefile` | All automation (see below) |
| `requirements.txt` | `litellm[proxy]`, `aip-proxy`, `psutil` |

## Common commands

```bash
make install          # Full setup: install rtk + configure Claude Code
make venv             # Create venv and install requirements.txt
make start            # Start LiteLLM (:4445) and aip-proxy (:4444) in background
make stop             # Kill processes on ports 4444 and 4445
make log-aip          # Tail aip-proxy.log
make log-litellm      # Tail litellm.log
make configure-claude # Patch ~/.claude/settings.json (timestamped backup created)
make unconfigure-claude # Restore last settings backup
make savings          # Live token savings dashboard — aip-proxy + rtk (refreshes every 2s, Ctrl+C to exit)
```

`configure_claude.py` can also be called directly:

```bash
python3 configure_claude.py apply    # point Claude at the proxy
python3 configure_claude.py restore  # roll back to last backup
```

## Architecture notes

- **aip-proxy** runs on `:4444` and forwards to LiteLLM on `:4445`. All external clients hit `:4444`.
- **LiteLLM** is configured entirely via `copilot-config.yaml`. Adding a new Copilot model only requires a new entry there (no Python changes).
- Every `github_copilot/*` model requires `Editor-Version` and `Copilot-Integration-Id` headers — these are set per-model in `copilot-config.yaml`.
- `configure_claude.py` sets four env vars in `~/.claude/settings.json` (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`). All other settings in the file are preserved.
- Backups of `settings.json` are named `settings.json.<YYYYMMDD_HHMMSS>.bak`; `restore` picks the lexicographically last one.
- Processes are tracked via `litellm.pid` / `aip-proxy.pid` (written by `make start`, used by `make stop` via `lsof -ti`).

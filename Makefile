# ── Variables ────────────────────────────────────────────────────────────────
AIP_PORT     := 4444
LITELLM_PORT := 4445

# Resolve user-local Python bin dir (works on macOS and Linux)
USER_PY_BIN := $(shell python3 -c "import site, os; print(os.path.join(site.getuserbase(),'bin'))" 2>/dev/null || echo $(HOME)/.local/bin)
export PATH := $(USER_PY_BIN):$(PATH)

POETRY := $(shell command -v poetry 2>/dev/null || echo $(USER_PY_BIN)/poetry)

# Sentinela: solo reinstala dependencias si pyproject.toml cambió
VENV_SENTINEL := .venv/.installed

.PHONY: venv start stop restart status log-aip log-litellm savings \
        clean-logs clean configure-claude unconfigure-claude install install-claude install-rtk help \
        _kill_ports

# help es el target por defecto
.DEFAULT_GOAL := help

# ── Help ─────────────────────────────────────────────────────────────────────
help:
	@echo ""
	@echo "  tokenlean — available targets:"
	@echo ""
	@echo "  make install             Full setup: venv + Claude + rtk + configure + start"
	@echo "  make venv                Install Poetry and project dependencies"
	@echo "  make start               Start LiteLLM (:$(LITELLM_PORT)) and aip-proxy (:$(AIP_PORT))"
	@echo "  make stop                Stop both services"
	@echo "  make restart             Stop then start"
	@echo "  make status              Show running/stopped state"
	@echo "  make log-aip             Tail aip-proxy log"
	@echo "  make log-litellm         Tail LiteLLM log"
	@echo "  make savings             Live token savings dashboard"
	@echo "  make clean-logs          Delete log files"
	@echo "  make clean               Delete logs, PIDs and virtualenv"
	@echo "  make configure-claude    Point Claude Code at the proxy"
	@echo "  make unconfigure-claude  Restore previous Claude settings"
	@echo "  make install-claude      Install Claude Code CLI (npm)"
	@echo "  make install-rtk         Install and configure rtk"
	@echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────

# kill_port <port>: kill any process on the given port (lsof → fuser fallback)
define kill_port
	@{ \
		PORT=$(1); \
		if command -v lsof >/dev/null 2>&1; then \
			PIDS=$$(lsof -ti :$$PORT 2>/dev/null); \
		elif command -v fuser >/dev/null 2>&1; then \
			PIDS=$$(fuser $$PORT/tcp 2>/dev/null); \
		else \
			PIDS=""; \
		fi; \
		if [ -n "$$PIDS" ]; then \
			echo "  Killing PID(s) $$PIDS on port $$PORT"; \
			kill -9 $$PIDS 2>/dev/null || true; \
		fi; \
	}
endef

# wait_port <port> <seconds>: wait until a TCP port accepts connections.
# Probes nc -z first; falls back to python3 socket (works on any Linux/macOS).
define wait_port
	@{ \
		PORT=$(1); MAX=$(2); i=0; \
		while [ $$i -lt $$MAX ]; do \
			OK=0; \
			if nc -z -w1 localhost $$PORT >/dev/null 2>&1; then \
				OK=1; \
			else \
				python3 -c \
					"import socket,sys; s=socket.socket(); s.settimeout(1); sys.exit(0 if s.connect_ex(('localhost',$$PORT))==0 else 1)" \
					2>/dev/null && OK=1; \
			fi; \
			[ $$OK -eq 1 ] && break; \
			sleep 1; i=$$((i+1)); \
		done; \
		if [ $$i -ge $$MAX ]; then \
			echo "  WARNING: port $$PORT did not open after $$MAX seconds — check litellm.log"; \
		fi; \
	}
endef

# ── Venv (idempotente) ────────────────────────────────────────────────────────
$(VENV_SENTINEL): pyproject.toml
	@if ! command -v poetry >/dev/null 2>&1; then \
		echo "Poetry not found. Installing..."; \
		python3 -m pip install --user poetry; \
	fi
	$(POETRY) config virtualenvs.in-project true
	$(POETRY) install
	@mkdir -p .venv && touch $(VENV_SENTINEL)

venv: $(VENV_SENTINEL)

# ── Targets ───────────────────────────────────────────────────────────────────

start: venv stop
	@echo "Starting LiteLLM on :$(LITELLM_PORT) and aip-proxy on :$(AIP_PORT)..."
	@nohup $(POETRY) run litellm --config copilot-config.yaml --port $(LITELLM_PORT) > litellm.log 2>&1 & PID=$$!; echo $$PID > litellm.pid
	@echo "  Waiting for LiteLLM to be ready..."
	$(call wait_port,$(LITELLM_PORT),120)
	@nohup $(POETRY) run aip-proxy start --target http://localhost:$(LITELLM_PORT) --port $(AIP_PORT) > aip-proxy.log 2>&1 & PID=$$!; echo $$PID > aip-proxy.pid
	@echo "  Done. LiteLLM PID=$$(cat litellm.pid)  aip-proxy PID=$$(cat aip-proxy.pid)"
	@echo "  Logs: litellm.log, aip-proxy.log"

# stop no depende de venv — matar procesos no requiere instalar nada
stop:
	@echo "Stopping services..."
	@BARE_METAL=0; \
	for pid_file in litellm.pid aip-proxy.pid; do \
		if [ -f $$pid_file ]; then \
			BARE_METAL=1; \
			PID=$$(cat $$pid_file); \
			if kill $$PID 2>/dev/null; then \
				echo "  Sent SIGTERM to PID $$PID ($$pid_file)"; \
			fi; \
			rm -f $$pid_file; \
		fi; \
	done; \
	if [ $$BARE_METAL -eq 1 ]; then \
		sleep 3; \
		$(MAKE) --no-print-directory _kill_ports; \
	fi
	@echo "  Done."

_kill_ports:
	$(call kill_port,$(AIP_PORT))
	$(call kill_port,$(LITELLM_PORT))

restart: stop start

status:
	@echo "── Service status ───────────────────────────────────────────"
	@if [ -f litellm.pid ]; then \
		PID=$$(cat litellm.pid); \
		if kill -0 $$PID 2>/dev/null; then \
			echo "  LiteLLM   : RUNNING  (PID $$PID, port $(LITELLM_PORT))"; \
		else \
			echo "  LiteLLM   : DEAD     (stale PID $$PID)"; \
		fi; \
	else \
		echo "  LiteLLM   : STOPPED"; \
	fi
	@if [ -f aip-proxy.pid ]; then \
		PID=$$(cat aip-proxy.pid); \
		if kill -0 $$PID 2>/dev/null; then \
			echo "  aip-proxy : RUNNING  (PID $$PID, port $(AIP_PORT))"; \
		else \
			echo "  aip-proxy : DEAD     (stale PID $$PID)"; \
		fi; \
	else \
		echo "  aip-proxy : STOPPED"; \
	fi
	@echo "─────────────────────────────────────────────────────────────"

log-aip:
	@tail -n 1000 -f aip-proxy.log

log-litellm:
	@tail -n 1000 -f litellm.log

savings: venv
	@$(POETRY) run python savings.py

clean-logs:
	@rm -f litellm.log aip-proxy.log
	@echo "  Logs deleted."

clean: stop clean-logs
	@rm -f litellm.pid aip-proxy.pid
	@rm -rf .venv
	@echo "  PIDs and virtualenv deleted."

configure-claude: venv
	@$(POETRY) run python configure_claude.py apply

unconfigure-claude: venv
	@$(POETRY) run python configure_claude.py restore

install: venv install-claude install-rtk configure-claude start

install-claude:
	@if command -v claude >/dev/null 2>&1; then \
		echo "  Claude Code already installed: $$(claude --version)"; \
	else \
		echo "Installing Claude Code..."; \
		if command -v npm >/dev/null 2>&1; then \
			npm install -g @anthropic-ai/claude-code; \
		else \
			echo "  ERROR: npm not found. Install Node.js (https://nodejs.org) then re-run."; \
			exit 1; \
		fi; \
		echo "  Claude Code installed: $$(claude --version)"; \
	fi

install-rtk:
	@echo "Installing rtk..."
	@if command -v rtk >/dev/null 2>&1; then \
		echo "  rtk already installed: $$(rtk --version)"; \
	else \
		if command -v brew >/dev/null 2>&1; then \
			brew install rtk; \
		else \
			curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; \
		fi; \
	fi
	@echo "Configuring rtk for Claude Code..."
	@export PATH="$$HOME/.local/bin:$$PATH"; rtk init -g --auto-patch
	@echo "Done. Restart Claude Code to activate the hook."

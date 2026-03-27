# Create virtual environment and install dependencies
venv:
	@if [ ! -d "venv" ]; then \
		python3 -m venv venv; \
	fi
	@. venv/bin/activate && pip install --upgrade pip && pip install -r requirements.txt

# Start LiteLLM proxy (depends on venv)
start: venv
	@echo "Starting LiteLLM and aip-proxy..."
	@. venv/bin/activate && nohup litellm --config copilot-config.yaml --port 4445 > litellm.log 2>&1 & echo $$! > litellm.pid
	@. venv/bin/activate && nohup aip-proxy start --target http://localhost:4445 --port 4444 > aip-proxy.log 2>&1 & echo $$! > aip-proxy.pid
	@echo "Processes started. Logs: litellm.log, aip-proxy.log"

# Stop running processes
stop:
	@echo "Stopping LiteLLM and aip-proxy..."
	@echo "Killing processes on ports 4444 and 4445..."
	@nohup kill -9 $$(lsof -ti :4444) >/dev/null 2>&1 &
	@nohup kill -9 $$(lsof -ti :4445) >/dev/null 2>&1 &
	@echo "Processes stopped."

# Attach aip-proxy log
log-aip:
	@tail -n 1000 -f aip-proxy.log

# Attach litellm log
log-litellm:
	@tail -n 1000 -f litellm.log


# Live token savings dashboard — aip-proxy + rtk (refreshes every 2s, Ctrl+C to exit)
savings:
	@python3 savings.py

# Clean log files
clean-logs:
	rm -f litellm.log aip-proxy.log

# Configure Claude Code to use the local proxy (backs up original settings)
configure-claude:
	@python3 configure_claude.py apply

# Restore Claude Code settings from the most recent backup
unconfigure-claude:
	@python3 configure_claude.py restore

# Full setup: install rtk + configure Claude to use the local proxy
install: install-rtk configure-claude

# Install rtk and configure it for Claude Code
install-rtk:
	@echo "Installing rtk..."
	@if command -v rtk &>/dev/null; then \
		echo "rtk already installed: $$(rtk --version)"; \
	else \
		if command -v brew &>/dev/null; then \
			brew install rtk; \
		else \
			curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; \
			export PATH="$$HOME/.local/bin:$$PATH"; \
		fi; \
	fi
	@echo "Configuring rtk for Claude Code..."
	@rtk init -g --auto-patch
	@echo "Done. Restart Claude Code to activate the hook."

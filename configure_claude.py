#!/usr/bin/env python3
"""
Configure or restore ~/.claude/settings.json to use the local tokenlean proxy.

Usage:
    python3 configure_claude.py apply    # point Claude at the local proxy
    python3 configure_claude.py restore  # restore the most recent backup
"""

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from glob import glob

SETTINGS_PATH = os.path.expanduser("~/.claude/settings.json")

PROXY_ENV = {
    "ANTHROPIC_AUTH_TOKEN": "litellm",
    "ANTHROPIC_BASE_URL": "http://localhost:4444",
    "ANTHROPIC_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_SMALL_FAST_MODEL": "gpt-4-1",
}


def _get_shell_path() -> str:
    """Return the PATH from the user's login shell, so VS Code inherits it."""
    shell = os.environ.get("SHELL", "/bin/bash")
    try:
        result = subprocess.run(
            [shell, "-lc", "echo $PATH"],
            capture_output=True, text=True, timeout=5,
        )
        path = result.stdout.strip()
        if path:
            return path
    except Exception:
        pass
    return os.environ.get("PATH", "")


def apply():
    if not os.path.exists(SETTINGS_PATH):
        # Ensure directory exists
        os.makedirs(os.path.dirname(SETTINGS_PATH), exist_ok=True)
        # Create a default settings file if it doesn't exist
        with open(SETTINGS_PATH, "w") as f:
            json.dump({"env": {}}, f, indent=2)
        print(f"Created new settings file at {SETTINGS_PATH}")

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = SETTINGS_PATH + f".{ts}.bak"
    shutil.copy(SETTINGS_PATH, bak)
    with open(SETTINGS_PATH) as f:
        data = json.load(f)
    data.setdefault("env", {}).update({k: v.strip() for k, v in PROXY_ENV.items()})
    # Also strip any pre-existing env values that may have stale whitespace/newlines
    data["env"] = {k: v.strip() if isinstance(v, str) else v for k, v in data["env"].items()}
    # Inject the login-shell PATH so VS Code / IDE extensions find binaries
    # installed via Homebrew, nvm, pyenv, etc. that aren't on the default PATH.
    shell_path = _get_shell_path()
    if shell_path:
        data["env"]["PATH"] = shell_path
    with open(SETTINGS_PATH, "w") as f:
        json.dump(data, f, indent=2)
    print(f"Done. Backup saved to {bak}")


def restore():
    pattern = SETTINGS_PATH + ".*.bak"
    backups = sorted(glob(pattern))
    if not backups:
        print(f"No backups found matching {pattern}", file=sys.stderr)
        sys.exit(1)
    latest = backups[-1]
    os.replace(latest, SETTINGS_PATH)
    print(f"Restored {SETTINGS_PATH} from {latest}")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("apply", "restore"):
        print(__doc__)
        sys.exit(1)
    {"apply": apply, "restore": restore}[sys.argv[1]]()

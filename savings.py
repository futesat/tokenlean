#!/usr/bin/env python3
"""
Live token savings dashboard — aip-proxy + rtk.
Refreshes every 2 seconds. Press Ctrl+C to exit.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime

REFRESH_INTERVAL = 2  # seconds
AIP_HEALTH_URL = "http://localhost:4444/health"

# ── ANSI helpers ─────────────────────────────────────────────────────────────

RESET  = "\033[0m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
CYAN   = "\033[36m"
RED    = "\033[31m"
WHITE  = "\033[97m"

def bold(s):   return f"{BOLD}{s}{RESET}"
def dim(s):    return f"{DIM}{s}{RESET}"
def green(s):  return f"{GREEN}{s}{RESET}"
def yellow(s): return f"{YELLOW}{s}{RESET}"
def cyan(s):   return f"{CYAN}{s}{RESET}"
def red(s):    return f"{RED}{s}{RESET}"


# ── Data fetchers ─────────────────────────────────────────────────────────────

def fetch_aip() -> dict | None:
    try:
        with urllib.request.urlopen(AIP_HEALTH_URL, timeout=2) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def fetch_rtk() -> str | None:
    try:
        result = subprocess.run(
            ["rtk", "gain"],
            capture_output=True, text=True, timeout=5
        )
        return result.stdout if result.returncode == 0 else None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


# ── Renderers ─────────────────────────────────────────────────────────────────

def render_aip(data: dict | None, width: int) -> list[str]:
    sep = "─" * width
    lines = [
        bold(cyan("  aip-proxy") + dim("  prompt compression · :4444")),
        dim(sep),
    ]
    if data is None:
        lines.append(f"  {yellow('⚠')}  not running — {dim('make start')}")
        return lines

    s = data.get("stats", {})
    reqs      = s.get("total_requests", 0)
    errors    = s.get("errors", 0)
    uptime    = int(s.get("uptime_seconds", 0))
    avg_ms    = s.get("avg_latency_ms", 0.0)
    level     = data.get("compression_level", "?")

    uptime_str = (
        f"{uptime // 3600}h {(uptime % 3600) // 60}m {uptime % 60}s"
        if uptime >= 3600
        else f"{uptime // 60}m {uptime % 60}s"
        if uptime >= 60
        else f"{uptime}s"
    )

    err_col = red(str(errors)) if errors else green(str(errors))

    lines += [
        f"  Requests        {bold(str(reqs))}",
        f"  Errors          {err_col}",
        f"  Compression lv  {bold(str(level))}",
        f"  Avg latency     {bold(f'{avg_ms:.0f} ms')}",
        f"  Uptime          {dim(uptime_str)}",
    ]
    return lines


def render_rtk(text: str | None, width: int) -> list[str]:
    sep = "─" * width
    lines = [
        bold(green("  rtk") + dim("  output compression")),
        dim(sep),
    ]
    if text is None:
        lines.append(f"  {yellow('⚠')}  not installed — {dim('make install-rtk')}")
        return lines

    # Pass the raw output lines through, stripping the outer frame lines
    # (═══ header/footer) but keeping everything else, indented by 2 spaces.
    for line in text.splitlines():
        stripped = line.rstrip()
        # Skip blank lines at start, keep the rest
        if stripped == "" and len(lines) == 2:
            continue
        lines.append("  " + stripped)
    return lines


# ── Main loop ─────────────────────────────────────────────────────────────────

def clear_screen():
    # Move cursor to top-left, then erase to end of screen
    sys.stdout.write("\033[H\033[J")
    sys.stdout.flush()


def hide_cursor():
    sys.stdout.write("\033[?1049h")  # enter alternate screen buffer
    sys.stdout.write("\033[?25l")    # hide cursor
    sys.stdout.flush()


def show_cursor():
    sys.stdout.write("\033[?25h")    # show cursor
    sys.stdout.write("\033[?1049l")  # exit alternate screen buffer (restores terminal)
    sys.stdout.flush()


def render():
    cols = shutil.get_terminal_size((80, 24)).columns
    width = min(cols - 2, 72)
    heavy = "━" * width

    aip_data = fetch_aip()
    rtk_text = fetch_rtk()

    now = datetime.now().strftime("%H:%M:%S")

    output = []
    output.append("")
    output.append(f"  {bold('tokenlean savings')}  {dim(f'updated {now} · Ctrl+C to exit')}")
    output.append(f"  {bold(heavy)}")
    output.append("")
    output.extend(render_aip(aip_data, width))
    output.append("")
    output.extend(render_rtk(rtk_text, width))
    output.append("")

    clear_screen()
    print("\n".join(output), end="", flush=True)


def main():
    hide_cursor()
    try:
        while True:
            render()
            time.sleep(REFRESH_INTERVAL)
    except KeyboardInterrupt:
        pass
    finally:
        show_cursor()
        print()  # clean newline on exit


if __name__ == "__main__":
    main()

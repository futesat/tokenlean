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

    reqs_s  = data.get("requests", {})
    comp_s  = data.get("compressor", {})
    cache_s = data.get("cache", {})

    total_reqs    = reqs_s.get("total_requests", 0)
    chat_reqs     = reqs_s.get("chat_requests", 0)
    cached_resp   = reqs_s.get("cached_responses", 0)
    streamed      = reqs_s.get("streamed_responses", 0)
    errors        = reqs_s.get("errors", 0)
    avg_ms        = reqs_s.get("avg_latency_ms", 0.0)
    p95_ms        = reqs_s.get("p95_latency_ms", 0.0)
    uptime        = int(reqs_s.get("uptime_seconds", 0))

    orig_chars    = comp_s.get("original_chars", 0)
    comp_chars    = comp_s.get("compressed_chars", 0)
    saved_chars   = comp_s.get("saved_chars", 0)
    savings_pct   = comp_s.get("savings_pct", 0.0)
    comp_calls    = comp_s.get("calls", 0)

    cache_entries = cache_s.get("entries", 0)
    cache_max     = cache_s.get("max_size", 0)
    cache_hits    = cache_s.get("hits", 0)
    cache_misses  = cache_s.get("misses", 0)
    cache_hr      = cache_s.get("hit_rate_pct", 0.0)
    cache_evict   = cache_s.get("evictions", 0)

    uptime_str = (
        f"{uptime // 3600}h {(uptime % 3600) // 60}m {uptime % 60}s"
        if uptime >= 3600
        else f"{uptime // 60}m {uptime % 60}s"
        if uptime >= 60
        else f"{uptime}s"
    )

    err_col    = red(str(errors)) if errors else green(str(errors))
    savings_col = green(f"{savings_pct:.1f}%") if savings_pct > 0 else dim("0%")
    hr_col     = green(f"{cache_hr:.1f}%") if cache_hr > 0 else dim("0%")

    lines += [
        dim("  ── requests ──────────────────────────────"),
        f"  Total           {bold(str(total_reqs))}",
        f"  Chat            {bold(str(chat_reqs))}   "
            + dim(f"cached {cached_resp}  streamed {streamed}"),
        f"  Errors          {err_col}",
        f"  Avg latency     {bold(f'{avg_ms:.0f} ms')}   "
            + dim(f"p95 {p95_ms:.0f} ms"),
        f"  Uptime          {dim(uptime_str)}",
        dim("  ── compressor ────────────────────────────"),
        f"  Calls           {bold(str(comp_calls))}",
        f"  Chars in/out    {bold(str(orig_chars))} → {bold(str(comp_chars))}   "
            + dim(f"saved {saved_chars}"),
        f"  Savings         {savings_col}",
        dim("  ── cache ─────────────────────────────────"),
        f"  Entries         {bold(str(cache_entries))} / {dim(str(cache_max))}   "
            + dim(f"evictions {cache_evict}"),
        f"  Hits / Misses   {bold(str(cache_hits))} / {bold(str(cache_misses))}   "
            + f"hit rate {hr_col}",
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

#!/usr/bin/env bash
# Kiosk session entrypoint. greetd autologins the agent user and runs this.
# cage (single-app Wayland compositor) hosts surf (suckless WebKit browser, no
# UI chrome) fullscreen on the local dashboard. surf is an X11 client; cage
# provides Xwayland automatically. Waits for the dashboard so we never flash an
# error page.
set -euo pipefail

DASHBOARD_URL="${DASHBOARD_URL:-http://127.0.0.1:8080}"

# Wait (max ~60s) for the dashboard to come up before opening the browser.
for _ in $(seq 1 60); do
  if curl -sf "${DASHBOARD_URL}/api/health" >/dev/null 2>&1; then break; fi
  sleep 1
done

# Wayland runtime dir for cage.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR"

# cage runs a single client fullscreen; surf has no toolbar => clean kiosk.
exec cage -- surf "$DASHBOARD_URL"

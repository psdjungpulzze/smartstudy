#!/bin/bash
# Ensures the Phoenix dev server is running and healthy after code changes.
# Called by Claude Code hooks after Elixir/HEEx file modifications.
#
# What it does:
#   1. Checks if the server responds on port 4040
#   2. If not, kills any zombie BEAM processes
#   3. Restarts via dev-app.sh
#   4. Waits for health check
#
# Exit codes:
#   0 = server is healthy
#   1 = server could not be recovered (needs manual intervention)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IW_DIR="$SCRIPT_DIR/interactor-workspace"
APP_PORT=4040
MAX_WAIT=45
RETRY_INTERVAL=3

check_health() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT/" 2>/dev/null)
  [[ "$code" -ge 200 && "$code" -lt 500 ]]
}

check_interactor() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:4002/health" 2>/dev/null)
  [[ "$code" -ge 200 && "$code" -lt 500 ]]
}

# Check Interactor services (silently restart if down)
if ! check_interactor; then
  if [[ -f "$IW_DIR/dev-services.sh" ]]; then
    echo "⚠️  Interactor services down — restarting..."
    "$IW_DIR/dev-services.sh" start >/dev/null 2>&1 &
  fi
fi

# Quick check — if healthy, nothing to do
if check_health; then
  exit 0
fi

# Give the live reloader a moment to finish recompiling
sleep 5

if check_health; then
  exit 0
fi

echo "⚠️  Server not responding on port $APP_PORT — recovering..."

# Count FunSheep BEAM processes only (not interactor-workspace services)
# Identify by working directory being the project root, not a subdirectory
funsheep_pids=""
for pid in $(ps aux | grep "[b]eam.smp" | awk '{print $2}'); do
  cwd=$(readlink /proc/$pid/cwd 2>/dev/null)
  if [[ "$cwd" == "$SCRIPT_DIR" ]]; then
    funsheep_pids="$funsheep_pids $pid"
  fi
done
funsheep_count=$(echo $funsheep_pids | wc -w | tr -d ' ')

if [[ "$funsheep_count" -gt 1 ]]; then
  echo "   Found $funsheep_count FunSheep BEAM processes (expected 1) — killing zombies..."
  echo $funsheep_pids | xargs kill -9 2>/dev/null
  sleep 2
elif [[ "$funsheep_count" -eq 1 ]]; then
  # Single process but not responding — kill it so dev-app.sh auto-restarts
  echo "   FunSheep process alive but not responding — killing for auto-restart..."
  echo $funsheep_pids | xargs kill -9 2>/dev/null
  sleep 2
fi

# Restart cleanly
echo "   Restarting server..."
cd "$SCRIPT_DIR"

# Source asdf if available
[[ -f "$HOME/.asdf/asdf.sh" ]] && source "$HOME/.asdf/asdf.sh"

./dev-app.sh start 2>/dev/null &
START_PID=$!

# Wait for health
elapsed=0
while [[ $elapsed -lt $MAX_WAIT ]]; do
  if check_health; then
    echo "✅ Server recovered and healthy on port $APP_PORT"
    exit 0
  fi
  sleep $RETRY_INTERVAL
  elapsed=$((elapsed + RETRY_INTERVAL))
done

echo "❌ Server did not recover within ${MAX_WAIT}s — check ./dev-app.sh logs"
exit 1

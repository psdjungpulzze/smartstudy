#!/usr/bin/env bash
# Visual test helper for Claude Code sessions.
# Starts a Phoenix server on a random port, runs Playwright verification,
# and cleans up afterwards.
#
# Each invocation uses a session ID (PID of the calling shell or explicit $SESSION_ID)
# so multiple Claude sessions can run isolated servers simultaneously.
#
# Usage:
#   ./scripts/i/visual-test.sh start          # Start server, print port
#   ./scripts/i/visual-test.sh stop           # Stop the server
#   ./scripts/i/visual-test.sh port           # Print current port
#   ./scripts/i/visual-test.sh url [path]     # Print full URL for a path
#   ./scripts/i/visual-test.sh status         # Check if server is running

set -euo pipefail

# Session ID — use PPID (parent shell) so start/stop/port calls from the
# same Claude session share the same server. Can be overridden via env.
SID="${SESSION_ID:-$PPID}"

PIDFILE="/tmp/funsheep-vt-${SID}.pid"
PORTFILE="/tmp/funsheep-vt-${SID}.port"
LOGFILE="/tmp/funsheep-vt-${SID}.log"

# Find an available port in range 4041-4099
find_port() {
  for _ in $(seq 1 20); do
    local port
    port=$(shuf -i 4041-4099 -n 1)
    if ! lsof -ti:"$port" >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
  done
  echo "ERROR: Could not find an available port in 4041-4099" >&2
  return 1
}

sweep_orphans() {
  # Find orphaned `mix phx.server` processes (PPID == 1) and kill them.
  # Scoped by command string so we don't touch unrelated Erlang VMs.
  local sweep_log="${LOGFILE%.log}.sweep.log"
  local orphans
  orphans=$(ps -eo pid,ppid,cmd 2>/dev/null | awk '$3 ~ /mix phx.server$/ && $2 == 1 { print $1 }')
  if [ -n "$orphans" ]; then
    echo "Sweeping orphaned mix phx.server processes: $orphans" >&2
    # shellcheck disable=SC2086
    echo "$orphans" | xargs -r kill 2>/dev/null || true
    # Brief grace period then SIGKILL any survivors.
    sleep 2
    # shellcheck disable=SC2086
    echo "$orphans" | xargs -r -I{} sh -c 'kill -0 {} 2>/dev/null && kill -9 {}' 2>/dev/null || true
    # Clean any pidfiles whose PIDs no longer exist.
    for f in /tmp/funsheep-vt-*.pid; do
      [ -f "$f" ] || continue
      local pid
      pid=$(cat "$f" 2>/dev/null)
      [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null && rm -f "$f" "${f%.pid}.port"
    done
    : > "$sweep_log" 2>/dev/null || true
  fi
}

cmd_start() {
  # Check if already running for this session
  if [ -f "$PORTFILE" ] && [ -f "$PIDFILE" ]; then
    local existing_port existing_pid
    existing_port=$(cat "$PORTFILE")
    existing_pid=$(cat "$PIDFILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
      echo "$existing_port"
      return 0
    fi
    # Stale files — clean up
    rm -f "$PIDFILE" "$PORTFILE"
  fi

  # Orphan sweep: any stale `mix phx.server` in THIS worktree whose parent
  # is init (PPID=1) is an orphan from a previous session that never got
  # stopped (Claude crash, terminal close, etc). Kill only those — leave
  # the user's own 4040 dev server alone, and leave sibling Claude sessions
  # alone (they're children of live shells, not init).
  sweep_orphans

  local port
  port=$(find_port)

  # Check if main server on 4040 is already running — if so, just use it
  # to avoid _build conflicts with protocol consolidation (Elixir 1.15 bug)
  if lsof -ti:4040 >/dev/null 2>&1; then
    echo "Using existing server on port 4040 (avoids _build conflicts)" >&2
    echo "4040" > "$PORTFILE"
    echo "0" > "$PIDFILE"
    echo "4040"
    return 0
  fi

  echo "Starting Phoenix server on port $port..." >&2
  PORT="$port" mix phx.server > "$LOGFILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PIDFILE"
  echo "$port" > "$PORTFILE"

  # Wait for server to be ready (up to 90s — first start may need to compile)
  local attempts=0
  while [ $attempts -lt 90 ]; do
    if curl -s -o /dev/null -w "" "http://localhost:$port/" 2>/dev/null; then
      echo "$port"
      return 0
    fi
    sleep 1
    attempts=$((attempts + 1))

    # Check if process died
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: Server process died. Check $LOGFILE" >&2
      rm -f "$PIDFILE" "$PORTFILE"
      return 1
    fi
  done

  echo "ERROR: Server did not start within 90s. Check $LOGFILE" >&2
  kill "$pid" 2>/dev/null || true
  rm -f "$PIDFILE" "$PORTFILE"
  return 1
}

cmd_stop() {
  if [ -f "$PIDFILE" ]; then
    local pid
    pid=$(cat "$PIDFILE")
    # pid=0 means we reused the main server — don't kill it
    if [ "$pid" != "0" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      # Wait for graceful shutdown
      local i=0
      while [ $i -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 0.5
        i=$((i + 1))
      done
      kill -9 "$pid" 2>/dev/null || true

      if [ -f "$PORTFILE" ]; then
        local port
        port=$(cat "$PORTFILE")
        echo "Stopped server on port $port" >&2
      fi
    elif [ "$pid" = "0" ]; then
      echo "Detached from main server (still running)" >&2
    fi
  fi

  rm -f "$PIDFILE" "$PORTFILE"
}

cmd_port() {
  if [ -f "$PORTFILE" ]; then
    local port
    port=$(cat "$PORTFILE")
    # Verify it's actually running
    if lsof -ti:"$port" >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
  fi
  echo "ERROR: No visual test server running for this session" >&2
  return 1
}

cmd_url() {
  local port
  port=$(cmd_port) || return 1
  local path="${1:-/}"
  echo "http://localhost:$port$path"
}

cmd_status() {
  if [ -f "$PORTFILE" ] && [ -f "$PIDFILE" ]; then
    local port pid
    port=$(cat "$PORTFILE")
    pid=$(cat "$PIDFILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo "running on port $port (pid $pid)"
      return 0
    fi
  fi
  echo "not running"
  return 1
}

case "${1:-help}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  port)   cmd_port ;;
  url)    cmd_url "${2:-/}" ;;
  status) cmd_status ;;
  *)
    echo "Usage: $0 {start|stop|port|url [path]|status}" >&2
    exit 1
    ;;
esac

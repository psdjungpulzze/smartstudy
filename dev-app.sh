#!/bin/bash

# Fun Sheep Development Manager
# Manages Docker containers and the Phoenix app
#
# Usage:
#   ./dev-app.sh start [--wait]   - Start Docker and app
#   ./dev-app.sh stop             - Stop the app
#   ./dev-app.sh restart [--wait] - Restart everything
#   ./dev-app.sh status           - Show status
#   ./dev-app.sh logs             - Tail the app log
#   ./dev-app.sh setup            - Run ecto.create + ecto.migrate + seeds
#
# Components:
#   1. Docker containers (PostgreSQL dev + test)
#   2. Fun Sheep Phoenix server (port 4040)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
PIDS_DIR="$SCRIPT_DIR/.dev-pids"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/server.log"
PID_FILE="$PIDS_DIR/fun-sheep.pid"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
ENV_CREDENTIALS_FILE="$SCRIPT_DIR/.env.credentials"
APP_PORT=4040

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WAIT_MODE=false
for arg in "$@"; do
  case $arg in
    --wait) WAIT_MODE=true ;;
  esac
done
COMMAND="${1:-}"

# =============================================================================
# Elixir Version Management
# =============================================================================

ensure_asdf() {
  if [[ -f "$HOME/.asdf/asdf.sh" ]]; then
    source "$HOME/.asdf/asdf.sh"
  elif [[ -d "$(brew --prefix asdf 2>/dev/null)/libexec" ]]; then
    source "$(brew --prefix asdf)/libexec/asdf.sh"
  fi
  if [[ -d "$HOME/.asdf/shims" ]]; then
    export PATH="$HOME/.asdf/shims:$PATH"
  fi
}

ensure_elixir_version() {
  if [[ ! -f "$SCRIPT_DIR/.tool-versions" ]]; then return 0; fi
  local expected_elixir
  expected_elixir=$(grep "^elixir " "$SCRIPT_DIR/.tool-versions" | awk '{print $2}')
  [[ -z "$expected_elixir" ]] && return 0
  local actual_elixir
  actual_elixir=$(elixir --version 2>/dev/null | grep "^Elixir" | awk '{print $2}')
  if [[ -z "$actual_elixir" ]]; then
    echo -e "${RED}[elixir]${NC} Elixir not found. Install via asdf: asdf install elixir $expected_elixir"
    return 1
  fi
  local expected_base="${expected_elixir%%-otp-*}"
  if [[ "$actual_elixir" != "$expected_base" ]]; then
    echo -e "${YELLOW}[elixir]${NC} Version mismatch: expected $expected_elixir, got $actual_elixir"
    rm -rf "$SCRIPT_DIR/_build"
    echo -e "${GREEN}[elixir]${NC} _build cleared. Will recompile on next run."
  fi
}

# =============================================================================
# Environment Management
# =============================================================================

load_env() {
  if [[ -f "$ENV_CREDENTIALS_FILE" ]]; then
    set -a; source "$ENV_CREDENTIALS_FILE"; set +a
  fi
}

# =============================================================================
# Docker Container Management
# =============================================================================

check_docker_available() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    return 1
  fi
  if ! docker info &> /dev/null 2>&1; then
    echo -e "${RED}Error: Docker daemon is not running.${NC}"
    return 1
  fi
  return 0
}

ensure_docker_containers() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo -e "${RED}[docker]${NC} docker-compose.yml not found"
    return 1
  fi
  local total_services running_count
  total_services=$(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null | wc -l | tr -d ' ')
  running_count=$(docker compose -f "$COMPOSE_FILE" ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$running_count" -ge "$total_services" ]]; then
    echo -e "${GREEN}[docker]${NC} Containers already running"
    return 0
  fi
  echo -e "${BLUE}[docker]${NC} Starting PostgreSQL containers..."
  docker compose -f "$COMPOSE_FILE" up -d 2>&1
  local max_wait=30 elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    local healthy
    healthy=$(docker compose -f "$COMPOSE_FILE" ps --status running -q 2>/dev/null | wc -l | tr -d ' ')
    [[ "$healthy" -ge "$total_services" ]] && echo -e "${GREEN}[docker]${NC} Containers healthy" && return 0
    sleep 2; elapsed=$((elapsed + 2))
  done
  echo -e "${YELLOW}[docker]${NC} Containers started (health check timed out)"
}

docker_status() {
  echo -e "${BLUE}Docker Containers:${NC}"
  if ! command -v docker &> /dev/null || ! docker info &> /dev/null 2>&1; then
    echo -e "  ${RED}Docker is not running${NC}"
    return
  fi
  while IFS= read -r svc; do
    local info
    info=$(docker compose -f "$COMPOSE_FILE" ps "$svc" --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | tail -n +2)
    if [[ -n "$info" ]]; then
      local cname cstatus
      cname=$(echo "$info" | awk '{print $1}')
      cstatus=$(echo "$info" | awk '{$1=""; print $0}' | sed 's/^ *//')
      if echo "$cstatus" | grep -q "Up"; then
        echo -e "  ${GREEN}$cname${NC} - $cstatus"
      else
        echo -e "  ${RED}$cname${NC} - ${cstatus:-Not running}"
      fi
    else
      echo -e "  ${RED}$svc${NC} - Not running"
    fi
  done < <(docker compose -f "$COMPOSE_FILE" config --services 2>/dev/null)
}

# =============================================================================
# Interactor Workspace Services
# =============================================================================

IW_DIR="$SCRIPT_DIR/interactor-workspace"

# Port assignments for interactor-workspace services (see interactor-workspace/CLAUDE.md).
iw_port_for() {
  case "$1" in
    account-server) echo 4001 ;;
    interactor) echo 4002 ;;
    service-knowledge-base) echo 4003 ;;
    billing-server) echo 4004 ;;
    user-knowledge-base) echo 4005 ;;
    interactor-user-database) echo 4007 ;;
    playwright-renderer) echo 3000 ;;
    jsonata-service) echo 3002 ;;
    *) echo "" ;;
  esac
}

check_iw_services() {
  # Explicit opt-out: someone else owns the interactor stack.
  if [[ -n "${SKIP_IW_SERVICES:-}" ]]; then
    echo -e "${BLUE}[iw-services]${NC} SKIP_IW_SERVICES set — not managing interactor services"
    return 0
  fi

  if [[ ! -f "$IW_DIR/dev-services.sh" ]]; then
    echo -e "${YELLOW}[iw-services]${NC} interactor-workspace not found, skipping"
    return 0
  fi

  local status_output
  status_output=$("$IW_DIR/dev-services.sh" status 2>/dev/null)
  local down_services=()

  # Parse "Application Services" section for "Not running" entries
  local in_app_section=false
  while IFS= read -r line; do
    if echo "$line" | grep -q "Application Services"; then
      in_app_section=true
      continue
    fi
    if [[ "$in_app_section" == true ]]; then
      # Skip stripe-webhooks and playwright-renderer (optional services)
      if echo "$line" | grep -q "stripe-webhooks\|playwright-renderer"; then
        continue
      fi
      if echo "$line" | grep -q "Not running"; then
        local svc
        svc=$(echo "$line" | sed 's/.*\[\(.*\)\].*/\1/')
        down_services+=("$svc")
      fi
    fi
  done <<< "$status_output"

  if [[ ${#down_services[@]} -eq 0 ]]; then
    echo -e "${GREEN}[iw-services]${NC} All required services running"
    return 0
  fi

  # Auto-detect external ownership: if a "down" service's port is already held,
  # another workspace is running it. Starting a duplicate would either fail to
  # bind or, worse, risk the sibling workspace's `dev-services.sh stop` killing
  # it later by port. Leave externally-held services alone.
  local to_start=()
  local externally_held=()
  for svc in "${down_services[@]}"; do
    local port
    port=$(iw_port_for "$svc")
    if [[ -n "$port" ]]; then
      local holder
      holder=$(lsof -ti:"$port" 2>/dev/null | head -1)
      if [[ -n "$holder" ]]; then
        externally_held+=("$svc (port $port, PID $holder)")
        continue
      fi
    fi
    to_start+=("$svc")
  done

  if [[ ${#externally_held[@]} -gt 0 ]]; then
    echo -e "${BLUE}[iw-services]${NC} Externally managed (port already held):"
    for entry in "${externally_held[@]}"; do
      echo "  • $entry"
    done
  fi

  if [[ ${#to_start[@]} -eq 0 ]]; then
    echo -e "${GREEN}[iw-services]${NC} Nothing to start (all down services are externally managed)"
    return 0
  fi

  echo -e "${YELLOW}[iw-services]${NC} Starting locally: ${to_start[*]}"
  for svc in "${to_start[@]}"; do
    echo -e "${BLUE}[iw-services]${NC} Starting $svc..."
    "$IW_DIR/dev-services.sh" start "$svc" 2>&1 | tail -3
  done
  return 0
}

# =============================================================================
# App Management
# =============================================================================

app_is_healthy() {
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$APP_PORT/" 2>/dev/null)
  [[ "$http_code" -ge 200 && "$http_code" -lt 500 ]]
}

# Headless-browser check: HTTP 200 is necessary but not sufficient. A Phoenix
# process can stay alive while LiveView hangs, JS assets 404, or the page
# renders as a blank white screen. Exit 0 only when the browser sees a real
# login page with no JS errors. Requires node + playwright (in ./node_modules).
visual_health_check() {
  local check_script="$SCRIPT_DIR/scripts/check-ui.mjs"
  local url="http://localhost:$APP_PORT"
  local path="${CHECK_UI_PATH:-/auth/login}"
  local selector="${CHECK_UI_SELECTOR:-#login-username}"

  if [[ "${SKIP_VISUAL_CHECK:-}" == "1" ]]; then
    echo -e "${BLUE}[visual-check]${NC} SKIP_VISUAL_CHECK=1 — skipping"
    return 0
  fi
  if [[ ! -f "$check_script" ]]; then
    echo -e "${YELLOW}[visual-check]${NC} $check_script not found, skipping"
    return 0
  fi
  if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}[visual-check]${NC} node not installed, skipping (install node or set SKIP_VISUAL_CHECK=1)"
    return 0
  fi

  echo -e "${BLUE}[visual-check]${NC} Rendering ${url}${path} in headless Chromium..."
  local output rc
  output=$(cd "$SCRIPT_DIR" && node "$check_script" "$url" "$path" "$selector" 2>&1)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    echo -e "${GREEN}[visual-check]${NC} $output"
    return 0
  fi

  echo -e "${RED}[visual-check]${NC} $output"
  case $rc in
    3) echo -e "${RED}[visual-check]${NC} Chromium browser binary missing. Run: npx playwright install chromium" ;;
    2) echo -e "${RED}[visual-check]${NC} Page loaded but JS errors were thrown — the UI is broken even though HTTP is 200." ;;
    *) echo -e "${RED}[visual-check]${NC} App is up on $APP_PORT but the UI is not rendering correctly." ;;
  esac
  echo -e "${YELLOW}[visual-check]${NC} Tail logs: ./dev-app.sh logs"
  return $rc
}

kill_app_process() {
  # Kill by PID file
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo -e "${YELLOW}[fun-sheep]${NC} Stopping stale process (PID: $pid)..."
      pkill -P "$pid" 2>/dev/null
      kill "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
  fi
  # Kill anything still on the port
  lsof -ti:$APP_PORT 2>/dev/null | xargs kill -9 2>/dev/null
  sleep 1
}

start_app() {
  # Check if already running AND healthy
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      if app_is_healthy; then
        echo -e "${GREEN}[fun-sheep]${NC} Already running and healthy (PID: $pid)"
        visual_health_check || true
        return 0
      else
        echo -e "${YELLOW}[fun-sheep]${NC} Process alive (PID: $pid) but not responding — restarting..."
        kill_app_process
      fi
    else
      echo -e "${YELLOW}[fun-sheep]${NC} Stale PID file (process gone) — cleaning up..."
      rm -f "$PID_FILE"
    fi
  fi
  # Also check if port is already in use
  local existing_pid
  existing_pid=$(lsof -ti:$APP_PORT 2>/dev/null)
  if [[ -n "$existing_pid" ]]; then
    echo -e "${YELLOW}[fun-sheep]${NC} Port $APP_PORT already in use (PID: $existing_pid). Killing..."
    kill "$existing_pid" 2>/dev/null
    sleep 1
    kill -0 "$existing_pid" 2>/dev/null && kill -9 "$existing_pid" 2>/dev/null
  fi
  mkdir -p "$LOG_DIR" "$PIDS_DIR"
  > "$LOG_FILE"
  echo -e "${BLUE}[fun-sheep]${NC} Starting on port $APP_PORT..."
  (
    cd "$APP_DIR"
    load_env
    # Auto-restart loop: if the server crashes (e.g., live reloader failure),
    # wait briefly and restart. Caps at 5 consecutive crashes to avoid infinite loops.
    MAX_CRASHES=5
    crash_count=0
    while true; do
      elixir --sname fun_sheep --cookie fun_sheep_dev -S mix phx.server >> "$LOG_FILE" 2>&1
      exit_code=$?
      crash_count=$((crash_count + 1))
      if [[ $crash_count -ge $MAX_CRASHES ]]; then
        echo "[fun-sheep] Crashed $MAX_CRASHES times in a row — giving up. Check $LOG_FILE" >> "$LOG_FILE"
        break
      fi
      echo "[fun-sheep] Server exited (code $exit_code), restarting in 3s... (crash $crash_count/$MAX_CRASHES)" >> "$LOG_FILE"
      # Clear port before restart
      lsof -ti:$APP_PORT 2>/dev/null | xargs kill -9 2>/dev/null
      sleep 3
    done
  ) &
  local pid=$!
  disown $pid 2>/dev/null
  echo $pid > "$PID_FILE"
  # Wait for HTTP health (up to 30s for compilation)
  local max_wait=30 elapsed=0
  echo -e "${BLUE}[fun-sheep]${NC} Waiting for HTTP health..."
  while [[ $elapsed -lt $max_wait ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo -e "${RED}[fun-sheep]${NC} Process died — check $LOG_FILE"
      rm -f "$PID_FILE"
      return 1
    fi
    if app_is_healthy; then
      echo -e "${GREEN}[fun-sheep]${NC} Started and healthy (PID: $pid) - Logs: $LOG_FILE"
      # HTTP is up; now confirm the browser actually renders the UI. A non-zero
      # return here is intentionally not fatal — caller keeps the server running
      # so the user can investigate logs. Failure is logged in red by the check.
      visual_health_check || true
      return 0
    fi
    sleep 2; elapsed=$((elapsed + 2))
  done
  # Process is alive but not responding yet — may still be compiling
  if kill -0 "$pid" 2>/dev/null; then
    echo -e "${YELLOW}[fun-sheep]${NC} Started (PID: $pid) but not yet responding — may still be compiling"
    echo -e "${YELLOW}[fun-sheep]${NC} Check: curl http://localhost:$APP_PORT/ or ./dev-app.sh logs"
  else
    echo -e "${RED}[fun-sheep]${NC} Failed to start — check $LOG_FILE"
    rm -f "$PID_FILE"
    return 1
  fi
}

stop_app() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo -e "${YELLOW}[fun-sheep]${NC} Stopping (PID: $pid)..."
      pkill -P "$pid" 2>/dev/null
      kill "$pid" 2>/dev/null
      sleep 1
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
      echo -e "${GREEN}[fun-sheep]${NC} Stopped"
    else
      echo -e "${YELLOW}[fun-sheep]${NC} Not running"
    fi
    rm -f "$PID_FILE"
  else
    echo -e "${YELLOW}[fun-sheep]${NC} Not running"
  fi
  lsof -ti:$APP_PORT | xargs kill -9 2>/dev/null
}

status_app() {
  if [[ -f "$PID_FILE" ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      echo -e "${GREEN}[fun-sheep]${NC} Running (PID: $pid, Port: $APP_PORT)"
      return
    fi
  fi
  echo -e "${RED}[fun-sheep]${NC} Not running (Port: $APP_PORT)"
}

# =============================================================================
# Database Setup
# =============================================================================

run_setup() {
  echo -e "${BLUE}[setup]${NC} Ensuring Docker containers are running..."
  check_docker_available || exit 1
  ensure_docker_containers
  load_env
  echo ""
  echo -e "${BLUE}[setup]${NC} Installing dependencies..."
  (cd "$APP_DIR" && mix deps.get)
  echo ""
  echo -e "${BLUE}[setup]${NC} Creating database..."
  (cd "$APP_DIR" && mix ecto.create)
  echo -e "${BLUE}[setup]${NC} Running migrations..."
  (cd "$APP_DIR" && mix ecto.migrate)
  echo -e "${BLUE}[setup]${NC} Running seeds..."
  (cd "$APP_DIR" && mix run priv/repo/seeds.exs)
  echo ""
  echo -e "${GREEN}[setup]${NC} Database setup complete!"
}

tail_logs() {
  echo -e "${BLUE}Tailing Fun Sheep logs (Ctrl+C to stop)${NC}"
  echo ""
  tail -f "$LOG_FILE" 2>/dev/null
}

# =============================================================================
# Init
# =============================================================================

mkdir -p "$PIDS_DIR" "$LOG_DIR"
ensure_asdf
ensure_elixir_version

# =============================================================================
# Command Dispatch
# =============================================================================

case "$COMMAND" in
  start)
    echo -e "${BLUE}=== Starting Fun Sheep ===${NC}"
    echo ""
    check_docker_available || exit 1
    ensure_docker_containers
    echo ""
    check_iw_services
    echo ""
    load_env
    echo ""
    start_app
    echo ""
    echo -e "${GREEN}=== Fun Sheep ready ===${NC}"
    echo "  App:  http://localhost:$APP_PORT"
    echo "  Logs: ./dev-app.sh logs"
    if [[ "$WAIT_MODE" == "true" ]]; then echo ""; tail_logs; fi
    ;;

  stop)
    echo -e "${BLUE}=== Stopping Fun Sheep ===${NC}"
    echo ""
    stop_app
    echo ""
    echo -e "${GREEN}=== Stopped ===${NC}"
    ;;

  restart)
    echo -e "${BLUE}=== Restarting Fun Sheep ===${NC}"
    echo ""
    stop_app
    echo ""
    sleep 1
    check_docker_available || exit 1
    ensure_docker_containers
    echo ""
    check_iw_services
    echo ""
    load_env
    echo ""
    start_app
    echo ""
    echo -e "${GREEN}=== Fun Sheep ready ===${NC}"
    echo "  App:  http://localhost:$APP_PORT"
    echo "  Logs: ./dev-app.sh logs"
    if [[ "$WAIT_MODE" == "true" ]]; then echo ""; tail_logs; fi
    ;;

  status)
    echo -e "${BLUE}=== Fun Sheep Status ===${NC}"
    echo ""
    docker_status
    echo ""
    status_app
    if app_is_healthy; then
      echo -e "  ${GREEN}HTTP health: OK${NC}"
    else
      echo -e "  ${RED}HTTP health: NOT RESPONDING${NC}"
    fi
    echo ""
    echo -e "${BLUE}Interactor Workspace Services:${NC}"
    if [[ -f "$IW_DIR/dev-services.sh" ]]; then
      "$IW_DIR/dev-services.sh" status 2>/dev/null | grep -E "^\[|Running|Not running"
    else
      echo -e "  ${YELLOW}Not available${NC}"
    fi
    ;;

  logs)
    tail_logs
    ;;

  setup)
    run_setup
    ;;

  check-ui)
    echo -e "${BLUE}=== Visual UI Check ===${NC}"
    echo ""
    visual_health_check
    exit $?
    ;;

  *)
    echo "Usage: $0 {start|stop|restart|status|logs|setup|check-ui} [--wait]"
    echo ""
    echo "Commands:"
    echo "  start    - Start Docker + app"
    echo "  stop     - Stop the app"
    echo "  restart  - Restart everything"
    echo "  status   - Show status"
    echo "  logs     - Tail the app log"
    echo "  setup    - Create + migrate database + seeds"
    echo "  check-ui - Render the login page in headless Chromium and report JS errors"
    echo ""
    echo "Env flags:"
    echo "  SKIP_IW_SERVICES=1   Don't manage interactor-workspace services (treat as external)"
    echo "  SKIP_VISUAL_CHECK=1  Skip the post-start Playwright UI check"
    echo "  CHECK_UI_PATH        Path to visual-check (default /auth/login)"
    echo "  CHECK_UI_SELECTOR    CSS selector to wait for (default #login-username)"
    echo ""
    echo "Components:"
    echo "  Docker   PostgreSQL dev (:5450) + test (:5451)"
    echo "  App      Fun Sheep (port $APP_PORT)"
    exit 1
    ;;
esac

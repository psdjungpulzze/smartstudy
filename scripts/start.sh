#!/usr/bin/env bash
# Development startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}StudySmart Development Server${NC}"
echo "================================"

# Check Docker
if ! docker info > /dev/null 2>&1; then
  echo -e "${RED}Docker is not running. Please start Docker first.${NC}"
  exit 1
fi

# Start Docker containers
echo -e "${YELLOW}Starting Docker containers...${NC}"
docker compose up -d

# Wait for PostgreSQL
echo -e "${YELLOW}Waiting for PostgreSQL...${NC}"
for i in {1..30}; do
  if docker exec study_smart_postgres_dev pg_isready -U postgres > /dev/null 2>&1; then
    echo -e "${GREEN}PostgreSQL is ready${NC}"
    break
  fi
  if [ $i -eq 30 ]; then
    echo -e "${RED}PostgreSQL failed to start${NC}"
    exit 1
  fi
  sleep 1
done

# Install deps if needed
if [ ! -d "_build" ] || [ ! -d "deps" ]; then
  echo -e "${YELLOW}Installing dependencies...${NC}"
  mix deps.get
fi

# Run migrations
echo -e "${YELLOW}Running migrations...${NC}"
mix ecto.migrate 2>/dev/null || mix ecto.setup

# Find available port
find_port() {
  local port=${1:-4040}
  local max=$((port + 100))
  while [ $port -lt $max ]; do
    if ! lsof -i :$port > /dev/null 2>&1; then
      echo $port
      return 0
    fi
    port=$((port + 1))
  done
  return 1
}

PORT=$(find_port 4040)
export PORT

echo ""
echo -e "${GREEN}Starting Phoenix on port $PORT...${NC}"
echo -e "Visit: ${GREEN}http://localhost:$PORT/dev/login${NC}"
echo ""

iex -S mix phx.server

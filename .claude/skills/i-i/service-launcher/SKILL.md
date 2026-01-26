---
name: service-launcher
description: Create a development services launcher script for consistent startup, logging, and process management across multiple services.
author: Interactor Workspace Practices
source_docs:
  - docs/i-i/interactor-workspace-docs/docs/development-practices.md#service-launcher-script
---

# Service Launcher Script

**Documentation:** `docs/i-i/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Managing multiple services in development
- Need consistent startup, logging, and process tracking
- Want to start/stop/restart all services with single commands
- Setting up a new multi-service project

## Features

- Start/stop/restart all services with one command
- File-based logging for AI accessibility
- Process tracking with PID files
- Status checking for all services
- Tail all logs simultaneously

## Implementation

Create `dev-services.sh` at project root with:

```bash
#!/bin/bash

# Development Services Launcher
# Usage:
#   ./dev-services.sh start    - Start all services
#   ./dev-services.sh stop     - Stop all services
#   ./dev-services.sh restart  - Restart services
#   ./dev-services.sh status   - Check service status
#   ./dev-services.sh logs     - Tail all logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDS_DIR="$SCRIPT_DIR/.dev-pids"

# SERVICE DEFINITIONS
# Format: "name|directory|command|port"
SERVICES=(
  "api|$SCRIPT_DIR/api|mix phx.server|4000"
  "worker|$SCRIPT_DIR/worker|mix run --no-halt|4001"
  "client|$SCRIPT_DIR/client|npm run dev|5173"
)

# [Full implementation in source docs]
```

## Usage

```bash
chmod +x dev-services.sh

./dev-services.sh start     # Start all services
./dev-services.sh stop      # Stop all services
./dev-services.sh restart   # Restart services
./dev-services.sh status    # Check which services are running
./dev-services.sh logs      # Tail all log files
./dev-services.sh start --wait  # Start and tail logs
```

## Customization Points

1. **SERVICES array**: Add your services with directories, commands, and ports
2. **Log file naming**: Modify based on your conventions
3. **Environment loading**: Script sources `.env` files automatically

## Instructions

1. Read the full script from the source documentation
2. Copy the complete `dev-services.sh` script to your project root
3. Update the SERVICES array with your project's services
4. Make executable: `chmod +x dev-services.sh`
5. Run `./dev-services.sh start` to begin development

## Related Skills

- `dev-logging` - Understanding file-based logging patterns

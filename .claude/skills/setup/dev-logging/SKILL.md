---
name: dev-logging
description: Setup file-based logging for AI-assisted debugging. Enables AI tools to read logs directly instead of requiring copy-paste from terminals.
author: Interactor Workspace Practices
source_docs:
  - docs/setup/interactor-workspace-docs/docs/development-practices.md#file-based-logging-for-ai-debugging
---

# File-Based Logging for AI Debugging

**Documentation:** `docs/setup/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Setting up a new project for AI-assisted development
- AI assistant cannot access logs from stdout/stderr
- Need persistent log files that survive terminal sessions
- Multiple tools need to monitor logs simultaneously

## The Problem

When services log only to stdout/stderr in a terminal, AI assistants cannot access the logs directly. They must ask the user to copy-paste log output, which is slow and error-prone.

## The Solution

Redirect all service output to log files that AI tools can read directly.

## Implementation

### 1. Create logs directory

```bash
mkdir -p logs
echo "logs/" >> .gitignore
```

### 2. Start services with output redirection

**Elixir/Phoenix:**
```bash
> logs/server.log
cd my-service
source .env
mix phx.server >> logs/server.log 2>&1 &
echo $! > .pid
```

**Node.js:**
```bash
npm run dev >> logs/dev.log 2>&1 &
```

### 3. Log file conventions

| Service Type | Log File |
|--------------|----------|
| Elixir/Phoenix | `logs/server.log` |
| Node.js | `logs/dev.log` |
| Python | `logs/app.log` |
| Go | `logs/server.log` |

### 4. Elixir Logger Configuration

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# config/dev.exs (simplified for development)
config :logger, :console,
  format: "[$level] $message\n"
```

## Benefits

- AI can read full log history with the Read tool
- AI can search logs with grep for specific errors
- Logs persist across terminal sessions
- Multiple tools can monitor logs simultaneously

## Related Skills

- `service-launcher` - Comprehensive service management with built-in logging

# Debug Logs (Production)

Diagnose production issues via SSH. **READ-ONLY** - find cause, do NOT change code.

> **Output:** Root cause analysis for local fix implementation.

## Environment Variables

Load from `.env`:
- `PRODUCTION_IP` - Production server IP address
- `PRODUCTION_USER` - SSH username for production server

## Execution

```
MAIN: Orchestrate
  ├─► Load env vars: source .env
  ├─► SSH connect: ssh $PRODUCTION_USER@$PRODUCTION_IP
  ├─► [PARALLEL] Explore: production logs
  └─► Synthesize → Report root cause
```

**SSH Commands:**
```bash
# Load environment
source .env

# Connect to production
ssh $PRODUCTION_USER@$PRODUCTION_IP

# Or run commands directly
ssh $PRODUCTION_USER@$PRODUCTION_IP "tail -100 /path/to/app/logs/error.log"
```

## Production Log Locations

| File | Contents |
|------|----------|
| `~/app/logs/error.log` | Errors/warnings |
| `~/app/logs/all.log` | All levels |
| `/var/log/syslog` | System logs |
| `journalctl -u myapp` | Systemd service logs |

**Common searches:**
```bash
# Recent errors
ssh $PRODUCTION_USER@$PRODUCTION_IP "tail -200 ~/app/logs/error.log"

# Search for specific error
ssh $PRODUCTION_USER@$PRODUCTION_IP "grep -B5 -A10 '[error_msg]' ~/app/logs/error.log"

# Phoenix/Elixir logs
ssh $PRODUCTION_USER@$PRODUCTION_IP "grep -E '(ERROR|WARN|exception|stacktrace)' ~/app/logs/all.log | tail -100"

# Check running processes
ssh $PRODUCTION_USER@$PRODUCTION_IP "ps aux | grep beam"

# Check application status
ssh $PRODUCTION_USER@$PRODUCTION_IP "systemctl status myapp"
```

## Analysis Focus

1. **Error patterns** - Recurring errors, frequency, timestamps
2. **Stack traces** - Full exception details
3. **Request context** - User, endpoint, parameters
4. **Resource issues** - Memory, CPU, connections
5. **External services** - Database, APIs, timeouts

## Output Format

```markdown
## Root Cause Analysis

### Issue
[Brief description]

### Evidence
- Log excerpt 1
- Log excerpt 2

### Root Cause
[Explanation with confidence level]

### Suggested Fix
[Code location and approach - DO NOT implement]

### Files to Modify
- `lib/module/file.ex:123` - [what to change]
```

## Constraints

- **NO CODE CHANGES** - Analysis only
- **NO FILE WRITES** - Read-only access
- **REPORT FINDINGS** - User implements fix locally
- **ASK IF UNSURE** - Production requires caution

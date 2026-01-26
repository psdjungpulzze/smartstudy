---
name: hot-reload
description: Setup hot code reloading API for updating running Elixir code without restarts. Enables rapid iteration and production debugging.
author: Interactor Workspace Practices
source_docs:
  - docs/i-i/interactor-workspace-docs/docs/development-practices.md#hot-code-reloading-api
---

# Hot Code Reloading API

**Documentation:** `docs/i-i/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Debugging production issues in real-time
- Testing fixes before committing
- Rapid iteration during development
- Need to update running code without service restart

## Architecture

```
┌─────────────────┐     POST /dev/hot-reload      ┌──────────────────┐
│  Developer /    │ ─────────────────────────────► │  Running Elixir  │
│  AI Assistant   │   { module, source }          │  Application     │
└─────────────────┘                               └──────────────────┘
                                                          │
                                                          ▼
                                                  ┌──────────────────┐
                                                  │ 1. Compile source│
                                                  │ 2. Purge old mod │
                                                  │ 3. Load new code │
                                                  └──────────────────┘
```

## Implementation Components

### 1. Authentication Plug

Create `lib/my_app_web/plugs/dev_auth.ex`:
- API key authentication using `DEV_API_KEY` environment variable
- Returns 503 when DEV_API_KEY not set (disabled in production)
- Uses `Plug.Crypto.secure_compare` to prevent timing attacks

### 2. Dev Controller

Create `lib/my_app_web/controllers/dev_controller.ex` with endpoints:
- `POST /dev/hot-reload` - Compile and load a module from source
- `POST /dev/eval` - Evaluate arbitrary Elixir code
- `GET /dev/modules` - List loaded modules matching a pattern
- `GET /dev/modules/:module` - Get module info (functions, etc.)

### 3. Router Setup

```elixir
pipeline :dev_auth do
  plug MyAppWeb.Plugs.DevAuth
end

scope "/dev", MyAppWeb do
  pipe_through :dev_auth

  post "/hot-reload", DevController, :hot_reload
  post "/eval", DevController, :eval
  get "/modules", DevController, :modules
  get "/modules/:module", DevController, :module_info
end
```

## Setup

### Generate API Key

```bash
openssl rand -base64 32
# Add to .env: DEV_API_KEY=<generated_key>
```

### Usage Examples

**Hot reload a module:**
```bash
python3 -c "
import json
with open('lib/my_app/some_module.ex', 'r') as f:
    source = f.read()
payload = {'module': 'MyApp.SomeModule', 'source': source}
print(json.dumps(payload))
" > /tmp/hotswap.json

curl -X POST http://localhost:4000/dev/hot-reload \
  -H "X-Dev-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/hotswap.json
```

**Evaluate code:**
```bash
curl -X POST http://localhost:4000/dev/eval \
  -H "X-Dev-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"code": "MyApp.Repo.aggregate(MyApp.User, :count)"}'
```

## Security Checklist

- [ ] API key is long and randomly generated
- [ ] `DEV_API_KEY` is NOT set in production (endpoints return 503)
- [ ] All requests are logged with warnings
- [ ] Uses `Plug.Crypto.secure_compare` to prevent timing attacks
- [ ] Consider IP whitelisting for additional security

## Instructions

1. Read the full implementation from source documentation
2. Create the DevAuth plug
3. Create the DevController
4. Add routes to router
5. Generate and configure DEV_API_KEY
6. Test with curl commands above

## Related Skills

- `dev-logging` - Enable AI to read logs for debugging

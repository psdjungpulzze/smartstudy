# Interactor Platform Integration Rules

When developing features related to Interactor services, you MUST read the relevant documentation before implementation.

## Trigger Keywords

Read the appropriate docs when the task involves ANY of these topics:

| Topic | Keywords | Documentation |
|-------|----------|---------------|
| **Authentication** | auth, login, JWT, token, OAuth, user management, admin, MFA | `docs/i/account-server-docs/integration-guide.md` |
| **AI Agents** | agent, AI agent, interactor agent, assistant, LLM | `docs/i/interactor-docs/integration-guide/04-ai-agents.md` |
| **Workflows** | workflow, automation, flow, pipeline | `docs/i/interactor-docs/integration-guide/05-workflows.md` |
| **Webhooks** | webhook, callback, event, streaming, SSE | `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md` |
| **Credentials** | credential, secret, API key, credential store | `docs/i/interactor-docs/integration-guide/03-credential-management.md` |
| **SDK** | SDK, client library, code example | `docs/i/interactor-docs/integration-guide/07-sdk-examples.md` |
| **Setup/Overview** | interactor setup, interactor overview | `docs/i/interactor-docs/integration-guide/01-overview.md`, `02-setup-and-authentication.md` |

## Documentation Locations (Submodules)

```
docs/i/
├── account-server-docs/          # Auth & Account management
│   └── integration-guide.md      # Full auth integration guide
│
└── interactor-docs/              # Interactor platform services
    └── integration-guide/
        ├── 01-overview.md        # Platform overview
        ├── 02-setup-and-authentication.md
        ├── 03-credential-management.md
        ├── 04-ai-agents.md       # AI agent integration
        ├── 05-workflows.md       # Workflow automation
        ├── 06-webhooks-and-streaming.md
        └── 07-sdk-examples.md    # Code examples
```

## Required Actions

1. **Before implementing**: Read the relevant doc(s) based on the task keywords
2. **Follow the patterns**: Use the exact API endpoints, request/response formats documented
3. **Use existing skills**: Invoke relevant skills in `.claude/skills/i/interactor-*` for guided implementation
4. **Validate**: Ensure implementation matches the documented specifications

## Related Skills

| Skill | Purpose |
|-------|---------|
| `interactor-auth` | Account Server authentication setup |
| `interactor-agents` | AI agent integration |
| `interactor-workflows` | Workflow automation |
| `interactor-webhooks` | Webhook & streaming setup |
| `interactor-credentials` | Credential management |
| `interactor-sdk` | SDK usage patterns |

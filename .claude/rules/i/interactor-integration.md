# Interactor Platform Integration Rules

## ⛔ STOP: Use Interactor First — Do NOT Reinvent

**Before building ANY feature, check this table.** If the feature you are about to build matches a row below, you MUST use the Interactor platform capability instead of coding it from scratch. Custom implementations are only permitted with an explicit ADR documenting why Interactor cannot be used.

### Interactor Capability Map

| If the task involves... | Interactor Already Provides | Documentation |
|---|---|---|
| Login, signup, password reset, user sessions, MFA, user management, admin panel | **Account Server** — full auth with JWT/RS256, JWKS, OAuth 2.0 | `docs/i/account-server-docs/integration-guide.md` |
| Storing OAuth tokens (Google, Slack, etc.), API keys, token refresh, secret vault | **Credential Management** — multi-tenant credential store with auto-refresh | `docs/i/interactor-docs/integration-guide/03-credential-management.md` |
| Chatbot, AI assistant, LLM integration, conversational UI, chat rooms, tool-calling | **AI Agents** — LLM assistants with tools, data sources, streaming | `docs/i/interactor-docs/integration-guide/04-ai-agents.md` |
| Multi-step process, approval flow, state machine, pipeline orchestration, automation | **Workflows** — state-machine engine with human-in-the-loop, forms | `docs/i/interactor-docs/integration-guide/05-workflows.md` |
| Real-time events, push notifications to backend, event-driven triggers, SSE | **Webhooks & Streaming** — event registration, signature verification, SSE | `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md` |
| Organizations, tenants, multi-tenant hierarchy, roles, permissions | **Account Server** — 4-tier hierarchy (Admin → Org → App → User) | `docs/i/account-server-docs/integration-guide.md` |
| Billing, payments, subscription management | **Billing Server** (Interactor Mode) or integrate server-to-server | Check deployment mode ADR |

### Common Reimplementation Mistakes — DO NOT BUILD These

| ❌ Do NOT build | ✅ Use instead |
|---|---|
| Custom JWT signing/verification | Interactor JWKS endpoint (`/oauth/jwks`) |
| Password hashing & session management | Interactor Account Server auth |
| OAuth token storage in your database | Interactor Credential Management API |
| Custom LLM chat interface from scratch | Interactor AI Agents with chat rooms |
| Custom workflow/state-machine engine | Interactor Workflows API |
| Custom webhook dispatcher | Interactor Webhooks with signature verification |
| User/org/role management CRUD | Interactor Account Server hierarchy |
| Custom token refresh logic for 3rd-party OAuth | Interactor Credential Management (auto-refresh) |

### When Custom Implementation IS Permitted

Only build custom implementations when ALL of these are true:
1. An ADR exists documenting the decision (created during Planning)
2. The ADR explains why Interactor's capability cannot meet the requirement
3. Valid reasons: compliance constraints, offline requirements, user base fully separate from Interactor ecosystem, Interactor doesn't cover the specific variant needed

## Trigger Keywords

Read the appropriate docs when the task involves ANY of these topics:

| Topic | Keywords | Documentation |
|-------|----------|---------------|
| **Authentication** | auth, login, JWT, token, OAuth, user management, admin, MFA, signup, password, session, SSO | `docs/i/account-server-docs/integration-guide.md` |
| **AI Agents** | agent, AI agent, assistant, LLM, chatbot, chat, conversational, GPT, Claude API, tool-calling | `docs/i/interactor-docs/integration-guide/04-ai-agents.md` |
| **Workflows** | workflow, automation, flow, pipeline, state machine, approval, multi-step, orchestration | `docs/i/interactor-docs/integration-guide/05-workflows.md` |
| **Webhooks** | webhook, callback, event, streaming, SSE, push notification, real-time event | `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md` |
| **Credentials** | credential, secret, API key, credential store, OAuth token, token storage, token refresh | `docs/i/interactor-docs/integration-guide/03-credential-management.md` |
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

1. **Before implementing**: Check the Capability Map above — if Interactor covers it, use Interactor
2. **Read the docs**: Read the relevant doc(s) for the Interactor service you will integrate
3. **Follow the patterns**: Use the exact API endpoints, request/response formats documented
4. **Use existing skills**: Invoke relevant skills in `.claude/skills/i/interactor-*` for guided implementation
5. **Validate**: Ensure implementation matches the documented specifications

## Related Skills

| Skill | Purpose |
|-------|---------|
| `interactor-auth` | Account Server authentication setup |
| `interactor-agents` | AI agent integration |
| `interactor-workflows` | Workflow automation |
| `interactor-webhooks` | Webhook & streaming setup |
| `interactor-credentials` | Credential management |
| `interactor-sdk` | SDK usage patterns |

# ADR-001: Use Interactor as the Core Platform for StudySmart

## Status

Accepted

## Date

2026-04-17

## Context

StudySmart requires several infrastructure capabilities that are complex to build from scratch:

- **Authentication and user management** -- secure login, JWT tokens, MFA, role-based access
- **AI agent orchestration** -- multi-agent pipelines for question generation, solving, and validation
- **Workflow automation** -- orchestrating OCR-to-question pipelines, spaced repetition scheduling, notification triggers
- **Credential management** -- securely storing API keys for Google Cloud Vision, LLM providers, and S3
- **Webhook and SSE streaming** -- real-time delivery of AI agent responses to the frontend

Building each of these as custom components would require months of development, introduce significant security risk, and create ongoing maintenance burden. The Interactor platform provides all of these as managed services with a consistent API surface.

The StudySmart team is already part of the Interactor ecosystem, which means single sign-on, shared tooling, and direct access to the platform team for support.

## Decision

StudySmart will use the Interactor platform as its core infrastructure layer for authentication, AI agent orchestration, workflow automation, credential management, and real-time streaming.

### Service Mapping

| StudySmart Feature | Interactor Service | Details |
|---|---|---|
| User login and registration | Interactor Account Server (OAuth/JWT) | RS256-signed JWTs, JWKS verification, SSO across ecosystem |
| Question Creator agent | Interactor AI Agents | Agent configured with textbook context, generates derivative questions |
| Question Solver agent | Interactor AI Agents | Independent agent that solves generated questions to verify answer correctness |
| Question Validator agent | Interactor AI Agents | Cross-checks Creator output against Solver output, flags discrepancies |
| Adaptive hint generation | Interactor AI Agents | On-demand agent that provides personalized hints during study sessions |
| Hobby contextualization | Interactor AI Agents | Agent that rewraps questions in user's hobby context |
| OCR-to-question pipeline | Interactor Workflows | Orchestrates: upload -> OCR -> chunking -> question generation -> validation -> storage |
| Spaced repetition scheduling | Interactor Workflows | Triggers review reminders based on SM-2/FSRS algorithm outputs |
| API keys (Google Cloud Vision, S3) | Interactor Credential Store | Centralized, encrypted credential storage with rotation support |
| Real-time AI responses | Interactor Webhooks + SSE | Stream agent responses to Phoenix LiveView via Server-Sent Events |

### Integration Points

```
StudySmart (Elixir/Phoenix)
    |
    |-- Auth ---------> Interactor Account Server (JWT verification via JWKS)
    |-- AI Agents ----> Interactor Agent API (REST + SSE streaming)
    |-- Workflows ----> Interactor Workflow API (trigger, monitor, callback)
    |-- Credentials --> Interactor Credential Store (read-only from app)
    |-- Events -------> Interactor Webhooks (inbound event notifications)
```

## Consequences

### Positive

- **Reduced development time**: Estimated 3-4 months saved by not building auth, agent orchestration, and workflow engine from scratch.
- **Security by default**: Authentication follows industry best practices (RS256, JWKS, token rotation) without the team needing to implement or maintain it.
- **Consistent ecosystem**: Users who already have Interactor accounts get SSO into StudySmart with zero friction.
- **Agent management UI**: Interactor provides a web interface for configuring and testing AI agents, reducing the need for custom admin tooling.
- **Operational visibility**: Interactor provides logging, monitoring, and cost tracking for agent invocations and workflow executions.
- **Credential security**: API keys for third-party services (Google Cloud Vision, S3) are stored in Interactor's encrypted credential store rather than in environment variables or application config.

### Negative

- **Platform dependency**: StudySmart cannot function without Interactor. An Interactor outage is a StudySmart outage for all AI and auth features.
- **API versioning risk**: Breaking changes in Interactor APIs would require StudySmart code changes. Mitigated by the team's proximity to the Interactor platform team.
- **Cost coupling**: AI agent usage costs flow through Interactor's billing. Cost optimization requires understanding both StudySmart usage patterns and Interactor pricing.
- **Vendor lock-in**: Migrating away from Interactor would require rebuilding auth, agent orchestration, workflows, and credential management -- essentially a rewrite of the infrastructure layer.
- **Debugging complexity**: Issues may span StudySmart and Interactor, requiring cross-system debugging. Mitigated by Interactor's logging and the team's access to both systems.

## Alternatives Considered

### 1. Custom Authentication (phx.gen.auth)

- **Pros**: No external dependency, full control, Phoenix has built-in scaffolding.
- **Cons**: Must implement password hashing, session management, MFA, token rotation, and security updates. No SSO with other ecosystem apps. Duplicates work already done by Interactor.
- **Rejected because**: The security risk of maintaining custom auth outweighs the independence benefit, especially when Interactor auth is production-proven and free for ecosystem apps.

### 2. Direct LLM API Calls (OpenAI/Anthropic SDKs)

- **Pros**: No middleware, lower latency, full control over prompts and model selection.
- **Cons**: Must build agent orchestration (multi-agent pipelines, retries, context management, streaming) from scratch. No centralized agent configuration or monitoring. Every app in the ecosystem would duplicate this work.
- **Rejected because**: The multi-agent question validation pipeline requires robust orchestration (sequential agent calls, result comparison, retry logic). Building this from scratch is estimated at 4-6 weeks and would lack the monitoring/management UI that Interactor provides.

### 3. Custom Workflow Engine (Oban-based)

- **Pros**: Elixir-native, leverages existing Oban dependency, no external service.
- **Cons**: Must build workflow definition, execution, monitoring, error handling, and retry logic. Oban handles job queuing but not multi-step workflow orchestration with branching and callbacks.
- **Rejected because**: The OCR-to-question pipeline has 5+ steps with conditional branching (e.g., skip OCR if text PDF, retry on low-confidence OCR). Interactor Workflows provides this out of the box with a visual editor and execution history.

### 4. Mix of Independent Services (Auth0 + LangChain + Temporal)

- **Pros**: Best-of-breed for each capability, no single vendor dependency.
- **Cons**: Three separate vendors to manage, three billing relationships, three sets of documentation, no unified monitoring. Integration complexity between services. Higher total cost.
- **Rejected because**: Operational complexity of managing multiple vendors outweighs the risk of depending on a single platform that the team already operates within.

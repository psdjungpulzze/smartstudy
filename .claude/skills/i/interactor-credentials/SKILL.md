---
name: interactor-credentials
description: Manage OAuth tokens and API keys for external services (Google, Slack, Salesforce, etc.) through Interactor.
author: Interactor Integration Guide
source_docs:
  - docs/i/interactor-docs/integration-guide/03-credential-management.md
---

# Interactor Credential Management Skill

**Documentation:** `docs/i/interactor-docs/integration-guide/03-credential-management.md`

## When to Use

- Connecting users to external OAuth services (Google, Slack, Salesforce)
- Implementing OAuth authorization flows
- Retrieving and refreshing access tokens for external APIs
- Securely storing API keys for non-OAuth services
- Monitoring credential status and handling revocations

## Prerequisites

- Interactor authentication configured (see `interactor-auth` skill)
- Understanding of OAuth 2.0 flows

## Instructions

Read the full documentation at the source path above for:
- OAuth flow implementation (initiate → callback → token retrieval)
- API key credential storage
- Token refresh and revocation handling
- Namespace strategy for multi-tenant isolation

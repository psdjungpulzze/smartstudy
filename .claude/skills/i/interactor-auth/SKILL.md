---
name: interactor-auth
description: Setup Interactor platform authentication with the Account Server (administrator registration, organizations, OAuth clients, users, tokens).
author: Interactor Integration Guide
source_docs:
  - docs/i/account-server-docs/integration-guide.md
---

# Interactor Authentication Skill

**Documentation:** `docs/i/account-server-docs/integration-guide.md`

## When to Use

- Registering as an Administrator and creating Organizations
- Setting up OAuth clients (Application credentials)
- Implementing user authentication flows (login, MFA, password reset)
- Managing JWT tokens (access, refresh, revocation)
- Configuring JWKS token verification

## Prerequisites

- Access to Interactor Account Server (`https://auth.interactor.com`)

## Instructions

Read the full documentation at the source path above for:
- Four-tier hierarchical auth model (Administrator → Organization → Application → Users)
- API endpoints and request/response formats
- JWT claims structure and token verification
- Code examples for all authentication flows

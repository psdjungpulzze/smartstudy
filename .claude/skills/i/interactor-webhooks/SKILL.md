---
name: interactor-webhooks
description: Receive real-time updates from Interactor via webhooks (push) or Server-Sent Events (pull).
author: Interactor Integration Guide
source_docs:
  - docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md
---

# Interactor Webhooks & Streaming Skill

**Documentation:** `docs/i/interactor-docs/integration-guide/06-webhooks-and-streaming.md`

## When to Use

- Monitoring credential status changes (expired, revoked)
- Receiving workflow completion notifications
- Streaming AI assistant responses in real-time
- Building live dashboards with workflow progress
- Implementing event-driven architecture with Interactor events

## Prerequisites

- Interactor authentication configured (see `interactor-auth` skill)
- HTTPS endpoint for webhooks (required for production)

## Instructions

Read the full documentation at the source path above for:
- Webhook registration and event types
- Signature verification for security
- Server-Sent Events (SSE) for real-time streaming
- When to use webhooks vs SSE (backend vs frontend)

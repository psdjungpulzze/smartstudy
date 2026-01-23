---
name: interactor-workflows
description: Build state-machine based automation with human-in-the-loop support through Interactor.
author: Interactor Integration Guide
source_docs:
  - docs/i/interactor-docs/integration-guide/05-workflows.md
---

# Interactor Workflows Skill

**Documentation:** `docs/i/interactor-docs/integration-guide/05-workflows.md`

## When to Use

- Implementing approval flows (expense reports, purchase orders)
- Building multi-step onboarding processes
- Order processing with status tracking
- Support ticket escalation with human handoffs
- Any multi-step process requiring conditional logic and user input

## Prerequisites

- Interactor authentication configured (see `interactor-auth` skill)
- Webhook endpoint for workflow notifications (recommended)

## Instructions

Read the full documentation at the source path above for:
- Workflow definition with states and transitions
- State types (action, halting, terminal)
- Instance creation and thread management
- Human-in-the-loop input handling

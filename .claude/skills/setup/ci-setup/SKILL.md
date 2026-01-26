---
name: ci-setup
description: Setup continuous integration with GitHub Actions for Elixir/Phoenix projects. Includes testing, formatting checks, compilation warnings, and Dialyzer.
author: Interactor Workspace Practices
source_docs:
  - docs/setup/interactor-workspace-docs/docs/development-practices.md#continuous-integration-setup
---

# Continuous Integration Setup

**Documentation:** `docs/setup/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Setting up a new Elixir/Phoenix project
- Need automated testing on push/PR
- Want to enforce code quality in CI
- Setting up Dialyzer for static type analysis

## CI Checks

| Check | Command | Purpose |
|-------|---------|---------|
| Formatting | `mix format --check-formatted` | Consistent code style |
| Compilation | `mix compile --warnings-as-errors` | No compiler warnings |
| Tests | `mix test` | All tests pass |
| Coverage | `mix test --cover` | Track test coverage (PRs only) |
| Dialyzer | `mix dialyzer` | Static type analysis |

## Implementation

### GitHub Actions Workflow

Create `.github/workflows/test.yml`:

```yaml
name: Test

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

env:
  MIX_ENV: test
  ELIXIR_VERSION: "1.18"
  OTP_VERSION: "27"

jobs:
  test:
    name: Test
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: my_app_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ env.ELIXIR_VERSION }}
          otp-version: ${{ env.OTP_VERSION }}

      - name: Cache deps
        uses: actions/cache@v4
        with:
          path: deps
          key: ${{ runner.os }}-mix-${{ hashFiles('**/mix.lock') }}

      - name: Cache _build
        uses: actions/cache@v4
        with:
          path: _build
          key: ${{ runner.os }}-build-${{ env.MIX_ENV }}-${{ hashFiles('**/mix.lock') }}

      - name: Install dependencies
        run: mix deps.get

      - name: Check formatting
        run: mix format --check-formatted

      - name: Compile (warnings as errors)
        run: mix compile --warnings-as-errors

      - name: Run migrations
        run: mix ecto.migrate

      - name: Run tests
        run: mix test --color

  dialyzer:
    name: Dialyzer
    runs-on: ubuntu-latest
    # ... (separate job with PLT caching)
```

## Adding PostgreSQL Extensions

For extensions like `pgvector`:

```yaml
- name: Setup database extensions
  run: |
    PGPASSWORD=postgres psql -h localhost -U postgres -d my_app_test \
      -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## Instructions

1. Copy the workflow file to `.github/workflows/test.yml`
2. Update environment variables for your Elixir/OTP versions
3. Update database name to match your project
4. Add any required PostgreSQL extensions
5. Configure Dialyzer job if using typespecs

## Related Skills

- `code-quality` - Local code quality enforcement

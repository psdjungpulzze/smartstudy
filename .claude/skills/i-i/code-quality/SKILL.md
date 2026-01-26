---
name: code-quality
description: Setup code quality enforcement for Elixir/Phoenix projects including formatter configuration, mix aliases, pre-commit workflow, and Dialyzer.
author: Interactor Workspace Practices
source_docs:
  - docs/i-i/interactor-workspace-docs/docs/development-practices.md#code-quality-enforcement
---

# Code Quality Enforcement

**Documentation:** `docs/i-i/interactor-workspace-docs/docs/development-practices.md`

## When to Use

- Setting up a new Elixir/Phoenix project
- Need consistent code formatting across team
- Want automated quality checks before commits
- Setting up Dialyzer for static type analysis

## Implementation

### 1. Elixir Formatter Configuration

Create `.formatter.exs`:

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{ex,exs}",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/*/seeds.exs"
  ]
]
```

### 2. Mix Aliases

Add to `mix.exs`:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup"],
    "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "test.cover": ["test --cover"],
    ci: [
      "format --check-formatted",
      "compile --warnings-as-errors",
      "test --cover"
    ]
  ]
end
```

### 3. Pre-Commit Workflow

Before every commit:

```bash
# 1. Format code
mix format

# 2. Verify formatting passes
mix format --check-formatted

# 3. Compile with warnings as errors
mix compile --warnings-as-errors

# 4. Run tests
mix test

# Or run all checks at once
mix ci
```

### 4. Dialyzer Setup

Add to `mix.exs` deps:

```elixir
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

Configure in `mix.exs`:

```elixir
defp project do
  [
    # ... other config
    dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  ]
end
```

First run builds the PLT (takes several minutes):

```bash
mkdir -p priv/plts
mix dialyzer
```

## Quick Commands

| Command | Purpose |
|---------|---------|
| `mix format` | Format all code |
| `mix format --check-formatted` | Check formatting (CI) |
| `mix compile --warnings-as-errors` | Compile strictly |
| `mix test` | Run tests |
| `mix test --cover` | Run with coverage |
| `mix ci` | Run all quality checks |
| `mix dialyzer` | Static type analysis |

## Instructions

1. Create/update `.formatter.exs` with imports for your deps
2. Add the aliases to `mix.exs`
3. Add `dialyxir` dependency
4. Configure Dialyzer PLT location
5. Run `mix ci` before commits

## Related Skills

- `ci-setup` - Automate these checks in GitHub Actions

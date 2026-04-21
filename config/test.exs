import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fun_sheep, FunSheep.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5449,
  database: "fun_sheep_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fun_sheep, FunSheepWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BmlTfSWIcAKIlIL8jrdMkmIRbrOau4hHxig315CZ5JkwSs46NbM4Oqmu95DaiLMn",
  server: false

# In test we don't send emails
config :fun_sheep, FunSheep.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Interactor configuration - always mock in tests
config :fun_sheep, interactor_mock: true

# Storage backend
config :fun_sheep, :storage_backend, FunSheep.Storage.Local

# Synthetic GCS config for tests that touch the GCS backend indirectly
# (e.g. OCR pipeline uses gcs_uri for bucket name). In mock mode no real
# GCS call is made, so the bucket name just has to exist.
config :fun_sheep, FunSheep.Storage.GCS,
  bucket: "fun-sheep-test-bucket",
  goth_name: FunSheep.Goth

# Let LiveView tests hit feature pages without first walking through
# /profile/setup. Real envs keep the gate on (defaults to true).
config :fun_sheep, :onboarding_gate, false

# OCR configuration - always mock in tests
config :fun_sheep, :ocr_mock, true

# Disable Oban in tests
config :fun_sheep, Oban, testing: :inline

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Enable dev routes in test for testing dev login and auth
config :fun_sheep, dev_routes: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

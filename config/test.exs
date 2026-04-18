import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :study_smart, StudySmart.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5449,
  database: "study_smart_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :study_smart, StudySmartWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "BmlTfSWIcAKIlIL8jrdMkmIRbrOau4hHxig315CZ5JkwSs46NbM4Oqmu95DaiLMn",
  server: false

# In test we don't send emails
config :study_smart, StudySmart.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Interactor configuration - always mock in tests
config :study_smart, interactor_mock: true

# Storage backend
config :study_smart, :storage_backend, StudySmart.Storage.Local

# OCR configuration - always mock in tests
config :study_smart, :ocr_mock, true

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Enable dev routes in test for testing dev login and auth
config :study_smart, dev_routes: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fun_sheep,
  ecto_repos: [FunSheep.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :fun_sheep, FunSheepWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FunSheepWeb.ErrorHTML, json: FunSheepWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FunSheep.PubSub,
  live_view: [signing_salt: "xGk+mfbZ"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :fun_sheep, FunSheep.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  fun_sheep: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  fun_sheep: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Oban background job processing
config :fun_sheep, Oban,
  repo: FunSheep.Repo,
  queues: [
    default: 10,
    ocr: 3,
    ai: 2,
    # PDF async OCR dispatch + poll. Low concurrency: pollers mostly snooze,
    # and a 1,000-page PDF spawns ~5 pollers so too much parallelism here
    # just consumes scheduler time and the Postgres update_all row lock
    # used for chunk status writes.
    pdf_ocr: 3,
    # Ingestion of large authoritative school/district/university registries
    # (NCES CCD ~130K rows, IPEDS ~6K, NEIS ~12K, GIAS ~32K, ROR ~100K).
    # Low concurrency: one job at a time keeps the DB write throughput
    # sane and avoids hammering upstream servers.
    ingest: 1
  ]

# Interactor integration (billing, auth, agents)
config :fun_sheep,
  interactor_mock: true,
  interactor_core_url: "https://core.interactor.com",
  interactor_billing_url: "https://billing.interactor.com",
  stripe_publishable_key: "mock"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

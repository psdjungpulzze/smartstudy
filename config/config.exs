# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fun_sheep,
  ecto_repos: [FunSheep.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: Atom.to_string(config_env())

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
  plugins: [
    # Hourly expiry of stale practice_requests (§4.5, §11.2).
    # Plugins are disabled automatically in test env (testing: :inline).
    {Oban.Plugins.Cron,
     crontab: [
       {"0 * * * *", FunSheep.Workers.RequestExpiryWorker},
       # Daily at 08:00 UTC — close the loop on pending TOC proposals
       # that nobody has approved after 14 days. See
       # FunSheep.Workers.TOCEscalationWorker for the logic.
       {"0 8 * * *", FunSheep.Workers.TOCEscalationWorker},
       # Every 15min — re-enqueue questions stuck at :pending after a
       # validation job was discarded (see StuckValidationSweeperWorker).
       {"*/15 * * * *", FunSheep.Workers.StuckValidationSweeperWorker},
       # Every 30min — recover discovered_sources stuck in scraping /
       # failed / unrun-discovered (Phase 5 — April audit had 32/33
       # sources stuck in non-terminal states, producing only 4 scraped
       # questions).
       {"*/30 * * * *", FunSheep.Workers.DiscoveredSourceSweeperWorker},
       # Nightly at 03:00 UTC — audit every ready course's
       # (chapter, difficulty) coverage and enqueue generation for
       # tuples below target. Phase 6 demand-driven supply loop.
       {"0 3 * * *", FunSheep.Workers.CoverageAuditWorker},
       # Sunday 23:55 UTC — compute weekly shout out winners so they are
       # ready for the Monday leaderboard. Keep in sync with runtime.exs.
       {"55 23 * * 0", FunSheep.Workers.ComputeShoutOutsWorker},
       # Nightly at 03:30 UTC — mark courses with 0 attempts and
       # no quality update in 90+ days as dormant (visibility_state: "reduced").
       {"30 3 * * *", FunSheep.Workers.MarkDormantContentWorker}
     ]}
  ],
  queues: [
    default: 10,
    ocr: 3,
    ai: 2,
    # Dedicated queue for QuestionValidationWorker — isolates it from the
    # generation/classification/extraction/scraping workers on `:ai` so a
    # noisy generation run doesn't starve validation (2026-04-22 incident).
    ai_validation: 2,
    # PDF async OCR dispatch + poll. Low concurrency: pollers mostly snooze,
    # and a 1,000-page PDF spawns ~5 pollers so too much parallelism here
    # just consumes scheduler time and the Postgres update_all row lock
    # used for chunk status writes.
    pdf_ocr: 3,
    # Ingestion of large authoritative school/district/university registries
    # (NCES CCD ~130K rows, IPEDS ~6K, NEIS ~12K, GIAS ~32K, ROR ~100K).
    # Low concurrency: one job at a time keeps the DB write throughput
    # sane and avoids hammering upstream servers.
    ingest: 1,
    # External LMS sync (Google Classroom, Canvas, …). Mostly network-bound;
    # low concurrency avoids bursting on provider rate limits.
    integrations: 3,
    # Parent notifications (weekly digest, opt-in alerts — spec §8). Swoosh
    # is I/O-bound and the digest fan-out is roughly one job per family.
    notifications: 2
  ]

# Interactor integration (billing, auth, agents)
config :fun_sheep,
  interactor_mock: false,
  interactor_core_url: "https://core.interactor.com",
  interactor_billing_url: "https://billing.interactor.com",
  interactor_skb_url: "https://skb.interactor.com",
  stripe_publishable_key: "mock"

# Feature flags — Postgres-backed with in-process ETS cache. Flags toggle
# in <1s across the cluster because Postgres LISTEN/NOTIFY pushes change
# events to every node.
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto,
  repo: FunSheep.Repo,
  ecto_table_name: "fun_with_flags_toggles"

config :fun_with_flags, :cache, enabled: true, ttl: 300

config :fun_with_flags, :cache_bust_notifications,
  enabled: true,
  adapter: FunWithFlags.Notifications.PhoenixPubSub,
  client: FunSheep.PubSub

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

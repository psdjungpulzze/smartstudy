import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/fun_sheep start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Load .env.credentials in dev/test for API keys
if config_env() in [:dev, :test] do
  credentials_path = Path.join([__DIR__, "..", ".env.credentials"])

  if File.exists?(credentials_path) do
    credentials_path
    |> File.read!()
    |> String.split("\n")
    |> Enum.each(fn line ->
      line = String.trim(line)

      if line != "" and not String.starts_with?(line, "#") do
        case String.split(line, "=", parts: 2) do
          [key, value] when key != "" ->
            System.put_env(String.trim(key), String.trim(value))

          _ ->
            :ok
        end
      end
    end)
  end
end

# Google Vision API key (from env or .env.credentials).
# Required in prod — without it, every OCR call returns HTTP 400 and uploaded
# materials silently end up in `:failed` status. Fail fast at boot rather than
# discovering this after a thousand failed jobs.
google_vision_api_key = System.get_env("GOOGLE_VISION_API_KEY")

if config_env() == :prod and (is_nil(google_vision_api_key) or google_vision_api_key == "") do
  raise """
  environment variable GOOGLE_VISION_API_KEY is missing.
  OCR cannot run without it — every uploaded material would fail.
  Set it in .env.prod and redeploy via scripts/deploy/deploy-prod.sh, which
  pushes it to Secret Manager as `google-vision-api-key`.
  """
end

if google_vision_api_key do
  config :fun_sheep, :google_vision_api_key, google_vision_api_key
end

if System.get_env("PHX_SERVER") do
  config :fun_sheep, FunSheepWeb.Endpoint, server: true
end

if config_env() == :prod do
  # Object storage: use GCS in production so uploads survive Cloud Run's
  # ephemeral filesystem and are shared across horizontally-scaled instances.
  gcs_bucket =
    System.get_env("GCS_BUCKET") ||
      raise """
      environment variable GCS_BUCKET is missing.
      Create the bucket with scripts/deploy/gcs-setup.sh and set GCS_BUCKET
      to its name (e.g. funsheep-uploads-prod).
      """

  config :fun_sheep, :storage_backend, FunSheep.Storage.GCS

  config :fun_sheep, FunSheep.Storage.GCS,
    bucket: gcs_bucket,
    goth_name: FunSheep.Goth

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  base_repo_config = [
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6
  ]

  # When deployed on Cloud Run with Cloud SQL via Unix socket,
  # DB_SOCKET_DIR is set (e.g. /cloudsql/PROJECT:REGION:INSTANCE)
  # and Postgrex uses the socket instead of the URL's host.
  repo_config =
    case System.get_env("DB_SOCKET_DIR") do
      nil -> base_repo_config
      socket_dir -> Keyword.put(base_repo_config, :socket_dir, socket_dir)
    end

  config :fun_sheep, FunSheep.Repo, repo_config

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :fun_sheep, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :fun_sheep, FunSheepWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # Oban: split architecture for Cloud Run.
  # The web service (funsheep-api) runs with RUN_OBAN_WORKERS unset —
  # Oban still accepts job inserts but processes no queues, so the container
  # is free to scale to zero. The dedicated funsheep-worker service runs
  # with RUN_OBAN_WORKERS=true and min-instances=1 to process background jobs.
  # Lifeline auto-recovers jobs orphaned by any unexpected container death.
  #
  # Concurrency tuning: ocr=8 balances throughput against the combined
  # pressure of Finch connection pools (GCS fetch + Vision OCR), DB
  # connection pool, and BEAM scheduler time. At ocr=15 under pool
  # pressure, the worker's own Oban.Peer/Notifier GenServer calls started
  # timing out at 5s, which cascaded into socket_closed failures across
  # all HTTP clients — the exact storm that killed OCR in April 2026.
  # ai=5 covers question generation + content discovery without saturating
  # the OpenAI rate limit on the Interactor agent endpoint.
  # POOL_SIZE on the worker container must be >= sum of these queues.
  oban_queues =
    if System.get_env("RUN_OBAN_WORKERS") == "true" do
      # ocr: 4 — fewer concurrent SSL handshakes to vision.googleapis.com.
      # Cloud Run's kernel rejects `sndbuf` as an SSL socket option when
      # too many connections are created at once, so we keep outbound
      # concurrency low and let in-process Req retries + Oban snooze
      # handle transient blips instead.
      [default: 10, ocr: 4, ai: 5, pdf_ocr: 3, ingest: 1]
    else
      false
    end

  config :fun_sheep, Oban,
    repo: FunSheep.Repo,
    queues: oban_queues,
    plugins: [
      Oban.Plugins.Pruner,
      {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(10)}
    ]

  interactor_client_id =
    System.get_env("INTERACTOR_CLIENT_ID") ||
      raise "environment variable INTERACTOR_CLIENT_ID is missing."

  interactor_client_secret =
    System.get_env("INTERACTOR_CLIENT_SECRET") ||
      raise "environment variable INTERACTOR_CLIENT_SECRET is missing."

  config :fun_sheep,
    interactor_mock: false,
    interactor_url: System.get_env("INTERACTOR_URL", "https://auth.interactor.com"),
    interactor_core_url: System.get_env("INTERACTOR_CORE_URL", "https://core.interactor.com"),
    interactor_ukb_url: System.get_env("INTERACTOR_UKB_URL", "https://ukb.interactor.com"),
    interactor_udb_url: System.get_env("INTERACTOR_UDB_URL", "https://udb.interactor.com"),
    interactor_org_name: System.get_env("INTERACTOR_ORG_NAME", "studysmart"),
    interactor_client_id: interactor_client_id,
    interactor_client_secret: interactor_client_secret

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :fun_sheep, FunSheepWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :fun_sheep, FunSheepWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :fun_sheep, FunSheep.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

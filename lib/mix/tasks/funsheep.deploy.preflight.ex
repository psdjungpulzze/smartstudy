defmodule Mix.Tasks.Funsheep.Deploy.Preflight do
  @shortdoc "Validate that an env file has every variable required for prod deploy"

  @moduledoc """
  Validate a deploy env file (default `.env.prod`) before invoking the actual
  Cloud Run deploy script. This is the canonical source of truth for "what
  must be set to deploy to prod" — the bash deploy script calls this task as
  its first step so the same checks run from CI, from a developer machine,
  or from `scripts/deploy/deploy-prod.sh`.

  Failures cause the task to exit non-zero, so it can be wired into CI or
  invoked from shell scripts via `mix funsheep.deploy.preflight && ...`.

  ## Usage

      mix funsheep.deploy.preflight                     # checks .env.prod
      mix funsheep.deploy.preflight --env-file PATH     # custom path

  ## What gets checked

    * Every variable in `@required_vars` is present and non-empty.
    * No value still contains the `XXXX` placeholder used in `.env.prod.example`.
    * Format checks for known-shape values (e.g. URLs are URL-shaped, the
      Google Vision API key starts with `AIza`).
  """

  use Mix.Task

  # Single source of truth for "what must be in .env.prod to deploy". Adding
  # a required variable here automatically guards both CI and the bash deploy.
  @required_vars [
    {"GCP_PROJECT_ID", :nonempty},
    {"GCP_REGION", :nonempty},
    {"CLOUD_RUN_SERVICE", :nonempty},
    {"DB_INSTANCE", :nonempty},
    {"PHX_HOST", :nonempty},
    {"INTERACTOR_URL", :url},
    {"INTERACTOR_CORE_URL", :url},
    {"INTERACTOR_UKB_URL", :url},
    {"INTERACTOR_UDB_URL", :url},
    {"INTERACTOR_ORG_NAME", :nonempty},
    {"INTERACTOR_CLIENT_ID", :nonempty},
    {"INTERACTOR_CLIENT_SECRET", :nonempty},
    {"GCS_BUCKET", :nonempty},
    {"GCS_SERVICE_ACCOUNT", :nonempty},
    {"GOOGLE_VISION_API_KEY", :google_api_key},
    {"SMTP_HOST", :nonempty},
    {"SMTP_PORT", :port},
    {"SMTP_USERNAME", :nonempty},
    {"SMTP_PASSWORD", :nonempty},
    {"MAILER_FROM", :email}
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [env_file: :string], aliases: [f: :env_file])

    env_file = opts[:env_file] || ".env.prod"

    unless File.exists?(env_file) do
      Mix.shell().error("Preflight FAILED: env file not found at #{env_file}")
      Mix.shell().info("  Copy .env.prod.example to .env.prod and fill in values.")
      exit({:shutdown, 1})
    end

    env = parse_env_file(env_file)
    failures = Enum.flat_map(@required_vars, &check(&1, env))

    if failures == [] do
      Mix.shell().info(
        "[ok] Preflight passed: #{length(@required_vars)} variable(s) checked in #{env_file}"
      )

      :ok
    else
      Mix.shell().error("Preflight FAILED for #{env_file}:")
      Enum.each(failures, fn msg -> Mix.shell().error("  - #{msg}") end)
      exit({:shutdown, 1})
    end
  end

  # Parse KEY=VALUE lines, ignoring blanks and comments. Strips matching
  # surrounding quotes since the bash deploy `source`s the file.
  defp parse_env_file(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: false)
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      cond do
        line == "" or String.starts_with?(line, "#") ->
          acc

        true ->
          case String.split(line, "=", parts: 2) do
            [key, value] ->
              key = String.trim(key)
              value = value |> String.trim() |> strip_quotes()
              Map.put(acc, key, value)

            _ ->
              acc
          end
      end
    end)
  end

  defp strip_quotes(<<?", rest::binary>>) do
    case String.split(rest, "\"", parts: 2) do
      [unquoted, _] -> unquoted
      _ -> rest
    end
  end

  defp strip_quotes(<<?', rest::binary>>) do
    case String.split(rest, "'", parts: 2) do
      [unquoted, _] -> unquoted
      _ -> rest
    end
  end

  defp strip_quotes(value), do: value

  defp check({key, kind}, env) do
    value = Map.get(env, key)

    cond do
      is_nil(value) or value == "" ->
        ["#{key} is missing or empty"]

      String.contains?(value, "XXXX") ->
        ["#{key} still contains the XXXX placeholder"]

      true ->
        format_check(key, kind, value)
    end
  end

  defp format_check(_key, :nonempty, _value), do: []

  defp format_check(key, :url, value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        []

      _ ->
        ["#{key} does not look like a URL: #{inspect(value)}"]
    end
  end

  defp format_check(key, :google_api_key, value) do
    if String.starts_with?(value, "AIza") and String.length(value) >= 35 do
      []
    else
      ["#{key} does not look like a Google API key (expected AIza... and >=35 chars)"]
    end
  end

  defp format_check(key, :port, value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 and n < 65_536 -> []
      _ -> ["#{key} is not a valid TCP port: #{inspect(value)}"]
    end
  end

  defp format_check(key, :email, value) do
    if Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, value) do
      []
    else
      ["#{key} does not look like an email address: #{inspect(value)}"]
    end
  end
end

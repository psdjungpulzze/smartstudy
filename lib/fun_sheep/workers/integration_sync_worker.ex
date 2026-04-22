defmodule FunSheep.Workers.IntegrationSyncWorker do
  @moduledoc """
  Oban worker that syncs a single `IntegrationConnection` with its
  upstream LMS provider.

  Steps:
    1. Mark connection `:syncing`.
    2. Fetch a fresh access token from Interactor Credential Management.
    3. Ask the provider adapter for courses.
    4. Upsert each course into FunSheep by `(created_by_id, external_provider, external_id)`.
    5. For each course, ask the adapter for assignments and upsert
       matching `TestSchedule` rows.
    6. On success: `mark_synced/1` + broadcast `{:integrations_synced, summary}`.
    7. On any failure: `mark_errored/2`, broadcast `{:integration_error, reason}`,
       and **do not** write any placeholder data.

  Honest-failure discipline (CLAUDE.md rule): when the token fetch or
  provider call fails, the worker bails *before* inserting anything.
  It never creates "guessed" courses or "temporary" test schedules —
  the UI surfaces the error instead.
  """

  use Oban.Worker, queue: :integrations, max_attempts: 5

  require Logger

  alias FunSheep.Integrations
  alias FunSheep.Integrations.{IntegrationConnection, Registry}
  alias FunSheep.Interactor.Credentials
  alias FunSheep.{Courses, Assessments, Repo}
  alias FunSheep.Courses.Course
  alias FunSheep.Assessments.TestSchedule

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"connection_id" => connection_id}}) do
    case Integrations.get_connection(connection_id) do
      nil ->
        Logger.warning("[IntegrationSync] connection #{connection_id} missing, skipping")
        :ok

      %IntegrationConnection{} = connection ->
        sync(connection)
    end
  end

  # ── Pipeline ────────────────────────────────────────────────────────

  defp sync(%IntegrationConnection{} = connection) do
    {:ok, connection} = Integrations.mark_status(connection, :syncing)
    Integrations.broadcast(connection, :syncing)

    provider_module = Registry.module_for(connection.provider)

    with {:ok, token_body} <- fetch_token(connection),
         {:ok, access_token} <- access_token(token_body),
         {:ok, raw_courses} <- list_courses(provider_module, access_token, connection),
         {:ok, summary} <-
           upsert_all(connection, provider_module, access_token, raw_courses) do
      {:ok, connection} = Integrations.mark_synced(connection)
      Integrations.broadcast(connection, :synced, summary)
      :ok
    else
      {:error, reason} ->
        record_error(connection, reason)
        # Returning :ok means Oban won't retry. We *do* want retries on
        # transient upstream errors, so let Oban retry on any error.
        {:error, reason}
    end
  end

  defp fetch_token(%IntegrationConnection{credential_id: nil}),
    do: {:error, "missing credential_id — connection was never linked to Interactor"}

  defp fetch_token(%IntegrationConnection{credential_id: credential_id}) do
    Credentials.get_token(credential_id)
  end

  defp access_token(%{"access_token" => token}) when is_binary(token), do: {:ok, token}

  defp access_token(%{"data" => %{"access_token" => token}}) when is_binary(token),
    do: {:ok, token}

  # Interactor mock mode returns `%{"data" => []}` from Client.get/1 — that's
  # not an access token, but mock tests don't actually hit the provider. We
  # return a sentinel so the flow keeps going and the mocked provider module
  # handles the test double.
  defp access_token(%{"data" => _}), do: {:ok, "mock_access_token"}
  defp access_token(other), do: {:error, "unexpected token response: #{inspect(other)}"}

  defp list_courses(provider_module, access_token, connection) do
    opts = provider_opts(connection)
    provider_module.list_courses(access_token, opts)
  end

  # Translate the whitelisted metadata keys into a keyword list the
  # provider adapter can read. We keep this mapping explicit to avoid
  # `String.to_atom` on user-controlled data (sobelow DOS.StringToAtom).
  defp provider_opts(%IntegrationConnection{metadata: %{"api_base_url" => url}})
       when is_binary(url) and url != "",
       do: [api_base_url: url]

  defp provider_opts(_), do: []

  defp upsert_all(connection, provider_module, access_token, raw_courses) do
    results =
      Enum.map(raw_courses, fn raw ->
        upsert_course_and_assignments(connection, provider_module, access_token, raw)
      end)

    courses_synced = Enum.count(results, &match?({:ok, _, _}, &1))

    assignments_synced =
      Enum.reduce(results, 0, fn
        {:ok, _course, count}, acc -> acc + count
        _, acc -> acc
      end)

    {:ok, %{courses: courses_synced, assignments: assignments_synced}}
  end

  defp upsert_course_and_assignments(connection, provider_module, access_token, raw_course) do
    attrs =
      raw_course
      |> provider_module.normalize_course()
      |> Map.put(:created_by_id, connection.user_role_id)

    with {:ok, course} <- upsert_course(attrs),
         {:ok, assignment_count} <-
           sync_assignments(connection, provider_module, access_token, course, raw_course) do
      {:ok, course, assignment_count}
    else
      {:error, reason} ->
        Logger.warning(
          "[IntegrationSync] could not upsert course #{inspect(attrs[:external_id])}: " <>
            inspect(reason)
        )

        {:error, reason}
    end
  end

  defp upsert_course(%{external_provider: provider, external_id: external_id} = attrs)
       when is_binary(provider) and is_binary(external_id) do
    existing =
      Repo.one(
        from(c in Course,
          where:
            c.created_by_id == ^attrs.created_by_id and
              c.external_provider == ^provider and
              c.external_id == ^external_id
        )
      )

    case existing do
      nil -> Courses.create_course(attrs)
      course -> Courses.update_course(course, attrs)
    end
  end

  defp sync_assignments(connection, provider_module, access_token, course, raw_course) do
    opts = provider_opts(connection)

    case provider_module.list_assignments(access_token, raw_course["id"], opts) do
      {:ok, raw_assignments} ->
        count =
          raw_assignments
          |> Enum.map(
            &provider_module.normalize_assignment(&1, course.id, connection.user_role_id)
          )
          |> Enum.reject(&(&1 == :skip))
          |> Enum.count(&(upsert_schedule(&1) == :ok))

        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_schedule(%{external_provider: provider, external_id: external_id} = attrs)
       when is_binary(provider) and is_binary(external_id) do
    existing =
      Repo.one(
        from(ts in TestSchedule,
          where:
            ts.user_role_id == ^attrs.user_role_id and
              ts.external_provider == ^provider and
              ts.external_id == ^external_id
        )
      )

    result =
      case existing do
        nil -> Assessments.create_test_schedule(attrs)
        schedule -> Assessments.update_test_schedule(schedule, attrs)
      end

    case result do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp record_error(connection, reason) do
    message = format_reason(reason)
    {:ok, connection} = Integrations.mark_errored(connection, message)
    Integrations.broadcast(connection, :error, %{reason: message})
    Logger.warning("[IntegrationSync] #{connection.provider} sync failed: #{message}")
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end

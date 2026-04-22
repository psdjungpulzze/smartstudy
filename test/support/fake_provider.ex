defmodule FunSheep.Integrations.Providers.Fake do
  @moduledoc """
  Test-only provider used by `FunSheep.Workers.IntegrationSyncWorkerTest`.

  Configuration lives in application env. Each test can set the shape of
  `:courses`, `:assignments`, and `:error` by putting a map under
  `:fake_provider` before calling the worker.
  """

  @behaviour FunSheep.Integrations.Provider

  @impl true
  def service_id, do: "google_classroom"

  @impl true
  def default_scopes, do: ["fake/scope"]

  @impl true
  def supported?, do: true

  @impl true
  def list_courses(_token, _opts \\ []) do
    state = Application.get_env(:fun_sheep, :fake_provider, %{})
    Map.get(state, :courses, {:ok, []})
  end

  @impl true
  def list_assignments(_token, course_id, _opts \\ []) do
    state = Application.get_env(:fun_sheep, :fake_provider, %{})

    state
    |> Map.get(:assignments, %{})
    |> case do
      {:error, _} = err -> err
      map when is_map(map) -> {:ok, Map.get(map, course_id, [])}
      list when is_list(list) -> {:ok, list}
    end
  end

  @impl true
  def normalize_course(%{"id" => id} = raw) do
    %{
      name: raw["name"] || "Fake Course",
      subject: raw["subject"] || "Math",
      grade: raw["grade"] || "10",
      external_provider: "google_classroom",
      external_id: id,
      external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: %{"source" => "fake"}
    }
  end

  @impl true
  def normalize_assignment(
        %{"id" => id, "due_at" => %Date{} = date, "name" => name},
        course_id,
        user_role_id
      ) do
    %{
      name: name,
      test_date: date,
      scope: %{"chapter_ids" => []},
      user_role_id: user_role_id,
      course_id: course_id,
      external_provider: "google_classroom",
      external_id: id,
      external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def normalize_assignment(_raw, _course, _user), do: :skip
end

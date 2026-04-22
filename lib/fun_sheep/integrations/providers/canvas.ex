defmodule FunSheep.Integrations.Providers.Canvas do
  @moduledoc """
  Canvas LMS adapter.

  Canvas is multi-tenant per institution — each school runs its own
  `<slug>.instructure.com` host. The host is carried on the
  `IntegrationConnection.metadata` map as `"api_base_url"`; the worker
  passes it to `list_courses/2` and `list_assignments/3` via opts.

  Any Canvas assignment with a future `due_at` is imported as a
  `TestSchedule`.

  Service slug: `canvas`
  """

  @behaviour FunSheep.Integrations.Provider

  require Logger

  @impl true
  def service_id, do: "canvas"

  @impl true
  def default_scopes do
    [
      "url:GET|/api/v1/courses",
      "url:GET|/api/v1/courses/:id/assignments"
    ]
  end

  @impl true
  def supported?, do: true

  @impl true
  def list_courses(access_token, opts) when is_binary(access_token) do
    with {:ok, host} <- fetch_host(opts) do
      url = "#{host}/api/v1/courses?enrollment_state=active&per_page=100"

      case http_get(url, access_token) do
        {:ok, courses} when is_list(courses) -> {:ok, courses}
        {:error, _} = err -> err
      end
    end
  end

  @impl true
  def list_assignments(access_token, course_id, opts)
      when is_binary(access_token) and (is_binary(course_id) or is_integer(course_id)) do
    with {:ok, host} <- fetch_host(opts) do
      url = "#{host}/api/v1/courses/#{course_id}/assignments?per_page=100"

      case http_get(url, access_token) do
        {:ok, items} when is_list(items) -> {:ok, items}
        {:error, _} = err -> err
      end
    end
  end

  @impl true
  def normalize_course(%{"id" => id} = raw) do
    %{
      name: raw["name"] || "Untitled course",
      subject: raw["course_code"] || raw["name"] || "General",
      grade: "Unknown",
      description: raw["public_description"] || raw["syllabus_body"],
      external_provider: service_id(),
      external_id: to_string(id),
      external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
      metadata: %{
        "source" => "canvas",
        "course_code" => raw["course_code"],
        "enrollment_term_id" => raw["enrollment_term_id"]
      }
    }
  end

  @impl true
  def normalize_assignment(%{"id" => id, "due_at" => due_at} = raw, local_course_id, user_role_id)
      when is_binary(due_at) do
    with {:ok, dt, _offset} <- DateTime.from_iso8601(due_at),
         date = DateTime.to_date(dt),
         true <- Date.compare(date, Date.utc_today()) != :lt do
      %{
        name: raw["name"] || "Untitled",
        test_date: date,
        scope: %{"chapter_ids" => []},
        user_role_id: user_role_id,
        course_id: local_course_id,
        external_provider: service_id(),
        external_id: to_string(id),
        external_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
    else
      _ -> :skip
    end
  end

  def normalize_assignment(_raw, _course_id, _user_role_id), do: :skip

  # ── Helpers ─────────────────────────────────────────────────────────

  defp fetch_host(opts) do
    case Keyword.get(opts, :api_base_url) do
      host when is_binary(host) and host != "" ->
        {:ok, String.trim_trailing(host, "/")}

      _ ->
        {:error,
         "Canvas requires an institution host (e.g. https://<school>.instructure.com). " <>
           "Ask the user for their Canvas URL before connecting."}
    end
  end

  defp http_get(url, access_token) do
    headers = [{"authorization", "Bearer #{access_token}"}]

    case Req.get(url, headers: headers) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, reason} -> {:error, reason}
    end
  end
end

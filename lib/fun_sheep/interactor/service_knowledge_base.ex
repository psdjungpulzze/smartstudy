defmodule FunSheep.Interactor.ServiceKnowledgeBase do
  @moduledoc """
  Interface to the Interactor Service Knowledge Base (SKB).

  SKB is the canonical registry for *service* metadata (auth provider,
  default scopes, API base URLs, capabilities) — as opposed to the
  User Knowledge Base which stores per-user content. Runs on port 4003
  locally; `skb.interactor.com` in prod.

  We use this to resolve provider slugs (e.g. `google_classroom`,
  `canvas`) to concrete service definitions before starting OAuth, so
  FunSheep never hardcodes provider base URLs or scopes.
  """

  require Logger

  @doc """
  Fetches a service definition by slug or id.

  Returns the raw SKB response map on success. Callers can read
  `"data.api_base_url"`, `"data.default_scopes"`, etc.
  """
  @spec get_service(String.t()) :: {:ok, map()} | {:error, term()}
  def get_service(slug_or_id) when is_binary(slug_or_id) do
    if mock_mode?() do
      {:ok, %{"data" => mock_service(slug_or_id)}}
    else
      http_get("/api/services/#{slug_or_id}")
    end
  end

  @doc "Returns the capability list for a service."
  @spec list_capabilities(String.t()) :: {:ok, map()} | {:error, term()}
  def list_capabilities(slug_or_id) when is_binary(slug_or_id) do
    if mock_mode?() do
      {:ok, %{"data" => []}}
    else
      http_get("/api/services/#{slug_or_id}/capabilities")
    end
  end

  @doc "Semantic search for services (e.g. `%{query: \"LMS\"}`)."
  @spec search_services(map()) :: {:ok, map()} | {:error, term()}
  def search_services(params) when is_map(params) do
    if mock_mode?() do
      {:ok, %{"data" => [], "total" => 0}}
    else
      with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
        case Req.post(base_url() <> "/api/services/search",
               json: params,
               headers: auth_headers(token)
             ) do
          {:ok, %{status: 200, body: body}} -> {:ok, body}
          {:ok, %{status: s, body: b}} -> {:error, {s, b}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp http_get(path) do
    with {:ok, token} <- FunSheep.Interactor.Auth.get_token() do
      case Req.get(base_url() <> path, headers: auth_headers(token)) do
        {:ok, %{status: 200, body: body}} -> {:ok, body}
        {:ok, %{status: s, body: b}} -> {:error, {s, b}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp base_url do
    Application.get_env(:fun_sheep, :interactor_skb_url, "https://skb.interactor.com")
  end

  defp mock_mode?, do: Application.get_env(:fun_sheep, :interactor_mock, false)

  # In mock mode we still need something halfway-real so adapters can read
  # `api_base_url` and `default_scopes` without crashing. The values here
  # mirror the adapter module declarations; they exist only to keep test
  # code path-compatible with prod.
  defp mock_service("google_classroom") do
    %{
      "id" => "svc_google_classroom",
      "slug" => "google_classroom",
      "name" => "Google Classroom",
      "api_base_url" => "https://classroom.googleapis.com",
      "default_scopes" => [
        "https://www.googleapis.com/auth/classroom.courses.readonly",
        "https://www.googleapis.com/auth/classroom.coursework.me.readonly"
      ]
    }
  end

  defp mock_service("canvas") do
    %{
      "id" => "svc_canvas",
      "slug" => "canvas",
      "name" => "Canvas LMS",
      "api_base_url" => nil,
      "default_scopes" => [
        "url:GET|/api/v1/courses",
        "url:GET|/api/v1/courses/:id/assignments"
      ]
    }
  end

  defp mock_service(slug) do
    %{"id" => "svc_#{slug}", "slug" => slug, "name" => slug, "default_scopes" => []}
  end
end

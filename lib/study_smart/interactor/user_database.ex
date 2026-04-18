defmodule StudySmart.Interactor.UserDatabase do
  @moduledoc """
  Interface to the Interactor User Database (UDB).

  Manages dynamic tables and natural-language queries over student data.
  Runs on port 4007 in the Interactor platform. Provides per-user
  data isolation so agents only access data for their assigned student.
  """

  @base_path "/api/v1/udb"

  @doc """
  Executes a natural-language or structured query against the UDB.

  `external_user_id` scopes the query to a specific user's data.
  `query` is either a natural-language string or a structured query map.
  """
  @spec query(String.t(), String.t() | map()) :: {:ok, map()} | {:error, term()}
  def query(external_user_id, query_input) do
    if mock_mode?() do
      {:ok, %{"data" => [], "query" => query_input}}
    else
      body = %{external_user_id: external_user_id, query: query_input}

      with {:ok, token} <- StudySmart.Interactor.Auth.get_token() do
        case Req.post(base_url() <> "#{@base_path}/query",
               json: body,
               headers: auth_headers(token)
             ) do
          {:ok, %{status: 200, body: resp_body}} -> {:ok, resp_body}
          {:ok, %{status: s, body: b}} -> {:error, {s, b}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc """
  Creates or registers a data entity (table/schema) in the UDB.

  `attrs` should include `:name`, `:schema`, and optionally `:description`.
  """
  @spec create_entity(map()) :: {:ok, map()} | {:error, term()}
  def create_entity(attrs) do
    if mock_mode?() do
      {:ok,
       %{
         "data" =>
           Map.merge(%{"id" => "mock_entity_#{:rand.uniform(100_000)}"}, stringify_keys(attrs))
       }}
    else
      with {:ok, token} <- StudySmart.Interactor.Auth.get_token() do
        case Req.post(base_url() <> "#{@base_path}/entities",
               json: attrs,
               headers: auth_headers(token)
             ) do
          {:ok, %{status: s, body: body}} when s in [200, 201] -> {:ok, body}
          {:ok, %{status: s, body: b}} -> {:error, {s, b}}
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  defp auth_headers(token), do: [{"authorization", "Bearer #{token}"}]

  defp base_url do
    Application.get_env(:study_smart, :interactor_udb_url, "http://localhost:4007")
  end

  defp mock_mode?, do: Application.get_env(:study_smart, :interactor_mock, true)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end

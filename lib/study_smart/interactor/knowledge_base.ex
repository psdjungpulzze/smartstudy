defmodule StudySmart.Interactor.KnowledgeBase do
  @moduledoc """
  Interface to the Interactor User Knowledge Base (UKB).

  Manages domain knowledge for hobbies and curriculum content
  via semantic search. Runs on port 4005 in the Interactor platform.
  """

  @base_path "/api/v1/knowledge"

  @doc """
  Searches the knowledge base with the given query parameters.

  `params` should include at minimum a `:query` key with the search text.
  Optional keys: `:category`, `:limit`, `:external_user_id`.
  """
  @spec search(map()) :: {:ok, map()} | {:error, term()}
  def search(params) do
    if mock_mode?() do
      {:ok, %{"data" => [], "total" => 0}}
    else
      with {:ok, token} <- StudySmart.Interactor.Auth.get_token() do
        case Req.post(base_url() <> "#{@base_path}/search",
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

  @doc """
  Stores a knowledge entry in the UKB.

  `attrs` should include `:content`, `:category`, and optionally
  `:external_user_id`, `:metadata`.
  """
  @spec store(map()) :: {:ok, map()} | {:error, term()}
  def store(attrs) do
    if mock_mode?() do
      {:ok,
       %{
         "data" =>
           Map.merge(%{"id" => "mock_kb_#{:rand.uniform(100_000)}"}, stringify_keys(attrs))
       }}
    else
      with {:ok, token} <- StudySmart.Interactor.Auth.get_token() do
        case Req.post(base_url() <> @base_path,
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
    Application.get_env(:study_smart, :interactor_ukb_url, "http://localhost:4005")
  end

  defp mock_mode?, do: Application.get_env(:study_smart, :interactor_mock, true)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end

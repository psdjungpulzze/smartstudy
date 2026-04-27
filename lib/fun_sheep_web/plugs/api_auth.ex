defmodule FunSheepWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates mobile API requests via a Bearer token (Interactor JWT).

  The mobile app obtains an access_token through the PKCE OAuth flow and
  sends it as `Authorization: Bearer <token>` on every API request.

  On success, sets:
    - conn.assigns.current_user_role  — FunSheep.Accounts.UserRole struct
    - conn.assigns.current_user       — map of user details (mirrors web session)

  Returns 401 JSON on missing or invalid token.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias FunSheep.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- extract_token(conn),
         {:ok, claims} <- decode_jwt(token),
         {:ok, user_role} <- resolve_user_role(claims) do
      user = %{
        "id" => user_role.id,
        "user_role_id" => user_role.id,
        "interactor_user_id" => user_role.interactor_user_id,
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "role" => to_string(user_role.role)
      }

      conn
      |> assign(:current_user_role, user_role)
      |> assign(:current_user, user)
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized", reason: to_string(reason)})
        |> halt()
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, :missing_token}
    end
  end

  defp decode_jwt(token) do
    with [_, payload, _] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} <- Jason.decode(json) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp resolve_user_role(%{"sub" => sub}) do
    case Accounts.get_user_role_by_interactor_id(sub) do
      nil -> {:error, :user_not_found}
      user_role -> {:ok, user_role}
    end
  end

  defp resolve_user_role(_), do: {:error, :invalid_claims}
end

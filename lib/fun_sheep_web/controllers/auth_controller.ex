defmodule FunSheepWeb.AuthController do
  @moduledoc """
  Handles Interactor OAuth 2.0 Authorization Code flow.

  Flow:
  1. GET /auth/login    → Redirect to Interactor /oauth/authorize
  2. GET /auth/callback → Exchange code for tokens, create session
  3. POST /auth/logout  → Clear session, redirect to login
  """
  use FunSheepWeb, :controller

  require Logger

  def login(conn, _params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32))

    authorize_url =
      interactor_url()
      |> URI.parse()
      |> Map.put(:path, "/oauth/authorize")
      |> URI.append_query(
        URI.encode_query(%{
          client_id: client_id(),
          redirect_uri: callback_url(conn),
          response_type: "code",
          scope: "openid profile email",
          state: state
        })
      )
      |> URI.to_string()

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: authorize_url)
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    saved_state = get_session(conn, :oauth_state)

    if state != saved_state do
      conn
      |> put_flash(:error, "Invalid OAuth state. Please try again.")
      |> redirect(to: ~p"/")
    else
      case exchange_code_for_tokens(code, conn) do
        {:ok, tokens} ->
          user = extract_user_from_tokens(tokens)

          conn
          |> delete_session(:oauth_state)
          |> put_session(:user_token, tokens["access_token"])
          |> put_session(:refresh_token, tokens["refresh_token"])
          |> put_session(:current_user, user)
          |> redirect(to: redirect_path_for_role(user["role"]))

        {:error, reason} ->
          Logger.error("OAuth token exchange failed: #{inspect(reason)}")

          conn
          |> put_flash(:error, "Login failed. Please try again.")
          |> redirect(to: ~p"/")
      end
    end
  end

  def callback(conn, %{"error" => error, "error_description" => description}) do
    Logger.warning("OAuth denied: #{error} - #{description}")

    conn
    |> put_flash(:error, "Login was denied: #{description}")
    |> redirect(to: ~p"/")
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid callback. Please try again.")
    |> redirect(to: ~p"/")
  end

  def session(conn, %{"token" => token}) do
    user = extract_user_from_tokens(%{"access_token" => token})

    conn
    |> put_session(:user_token, token)
    |> put_session(:current_user, user)
    |> redirect(to: redirect_path_for_role(user["role"]))
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end

  # --- Private ---

  defp exchange_code_for_tokens(code, conn) do
    url = "#{interactor_url()}/oauth/token"

    body = [
      grant_type: "authorization_code",
      client_id: client_id(),
      client_secret: client_secret(),
      code: code,
      redirect_uri: callback_url(conn)
    ]

    case Req.post(url, form: body) do
      {:ok, %{status: 200, body: tokens}} ->
        {:ok, tokens}

      {:ok, %{status: status, body: resp}} ->
        {:error, {status, resp}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_user_from_tokens(tokens) do
    # Decode the access token to get user info (JWT claims)
    # The Interactor User JWT contains: sub, type, org, username, metadata
    case decode_jwt(tokens["access_token"]) do
      {:ok, claims} ->
        %{
          "id" => claims["sub"],
          "interactor_user_id" => claims["sub"],
          "email" => claims["email"] || claims["username"],
          "display_name" => claims["name"] || claims["username"] || "User",
          "role" => get_in(claims, ["metadata", "role"]) || "student",
          "org" => claims["org"]
        }

      {:error, _} ->
        # Fallback: minimal user from token response
        %{
          "id" => "unknown",
          "interactor_user_id" => "unknown",
          "email" => "user@example.com",
          "display_name" => "User",
          "role" => "student"
        }
    end
  end

  defp decode_jwt(token) when is_binary(token) do
    # Decode without verification for extracting claims
    # Actual verification happens in the auth plug via JWKS
    case String.split(token, ".") do
      [_, payload, _] ->
        case Base.url_decode64(payload, padding: false) do
          {:ok, json} -> Jason.decode(json)
          :error -> {:error, :invalid_base64}
        end

      _ ->
        {:error, :invalid_jwt}
    end
  end

  defp decode_jwt(_), do: {:error, :no_token}

  defp redirect_path_for_role("parent"), do: "/parent"
  defp redirect_path_for_role("teacher"), do: "/teacher"
  defp redirect_path_for_role("admin"), do: "/admin"
  defp redirect_path_for_role(_), do: "/dashboard"

  defp callback_url(_conn) do
    FunSheepWeb.Endpoint.url() <> "/auth/callback"
  end

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp client_id, do: Application.get_env(:fun_sheep, :interactor_client_id, "")
  defp client_secret, do: Application.get_env(:fun_sheep, :interactor_client_secret, "")
end

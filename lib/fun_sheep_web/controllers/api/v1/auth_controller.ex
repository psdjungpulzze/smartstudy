defmodule FunSheepWeb.API.V1.AuthController do
  @moduledoc """
  Mobile OAuth PKCE authentication endpoints.

  Flow:
  1. GET  /api/v1/auth/authorize_url   — returns Interactor authorize URL with PKCE challenge
  2. POST /api/v1/auth/token            — exchanges code + code_verifier for tokens
  3. POST /api/v1/auth/refresh          — refreshes an access token

  The mobile app opens the authorize URL in a WebBrowser session. Interactor
  redirects back to `funsheep://auth/callback?code=...` which the app intercepts,
  then calls /api/v1/auth/token to complete the exchange.
  """

  use FunSheepWeb, :controller

  alias FunSheep.Accounts

  require Logger

  @doc """
  Returns the Interactor OAuth authorize URL for the mobile app to open.

  Params (query string):
    - redirect_uri     — deep link URI (e.g. funsheep://auth/callback)
    - code_challenge   — PKCE S256 challenge (base64url of SHA-256 of verifier)
    - idp_hint         — (optional) "google" | "github" | "apple"
  """
  def authorize_url(conn, params) do
    redirect_uri = params["redirect_uri"] || default_mobile_redirect()
    code_challenge = params["code_challenge"]

    unless code_challenge do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "code_challenge is required"})
      |> halt()
    end

    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    query =
      %{
        client_id: client_id(),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "openid profile email",
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }
      |> maybe_add_idp_hint(params["idp_hint"])

    authorize_url =
      interactor_url()
      |> URI.parse()
      |> Map.put(:path, "/oauth/authorize")
      |> URI.append_query(URI.encode_query(query))
      |> URI.to_string()

    json(conn, %{authorize_url: authorize_url, state: state})
  end

  @doc """
  Exchanges an authorization code for tokens.

  Body (JSON):
    - code            — authorization code from the OAuth callback
    - code_verifier   — PKCE verifier (plain text, before hashing)
    - redirect_uri    — must match the URI used to get the code
  """
  def token(conn, %{"code" => code, "redirect_uri" => redirect_uri} = params) do
    code_verifier = params["code_verifier"]

    case exchange_code(code, code_verifier, redirect_uri) do
      {:ok, tokens} ->
        user = extract_and_upsert_user(tokens)
        json(conn, %{data: %{tokens: tokens_payload(tokens), user: user_payload(user)}})

      {:error, reason} ->
        Logger.warning("[API.Auth] token exchange failed: #{inspect(reason)}")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "token_exchange_failed"})
    end
  end

  def token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "code and redirect_uri are required"})
  end

  @doc """
  Refreshes an access token using a refresh token.

  Body (JSON):
    - refresh_token
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    url = "#{interactor_url()}/oauth/token"

    body = [
      grant_type: "refresh_token",
      client_id: client_id(),
      client_secret: client_secret(),
      refresh_token: refresh_token
    ]

    case Req.post(url, form: body) do
      {:ok, %{status: 200, body: tokens}} ->
        json(conn, %{data: tokens_payload(tokens)})

      {:ok, %{status: status}} ->
        Logger.warning("[API.Auth] refresh failed: HTTP #{status}")

        conn
        |> put_status(:unauthorized)
        |> json(%{error: "refresh_failed"})

      {:error, reason} ->
        Logger.error("[API.Auth] refresh error: #{inspect(reason)}")

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "upstream_error"})
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "refresh_token is required"})
  end

  # --- Private ---

  defp exchange_code(code, code_verifier, redirect_uri) do
    url = "#{interactor_url()}/oauth/token"

    body =
      [
        grant_type: "authorization_code",
        client_id: client_id(),
        client_secret: client_secret(),
        code: code,
        redirect_uri: redirect_uri
      ]
      |> then(fn b ->
        if code_verifier, do: Keyword.put(b, :code_verifier, code_verifier), else: b
      end)

    case Req.post(url, form: body) do
      {:ok, %{status: 200, body: tokens}} -> {:ok, tokens}
      {:ok, %{status: status, body: resp}} -> {:error, {status, resp}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_and_upsert_user(tokens) do
    access_token = tokens["access_token"]

    with [_, payload, _] <- String.split(access_token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"sub" => sub, "org" => org} = claims} <- Jason.decode(json) do
      profile = fetch_interactor_profile(sub, org)
      email = profile["email"] || claims["username"]
      display_name = profile["username"] || claims["username"] || "User"
      role = get_in(profile, ["metadata", "role"]) || "student"
      db_role = if role in ~w(student parent teacher admin), do: role, else: "student"

      user_role_id =
        case Accounts.get_user_role_by_interactor_id_and_role(sub, db_role) do
          %Accounts.UserRole{} = ur ->
            Accounts.update_user_role(ur, %{
              last_login_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

            ur.id

          nil ->
            case Accounts.create_user_role(%{
                   interactor_user_id: sub,
                   role: db_role,
                   email: email || "unknown@example.com",
                   display_name: display_name,
                   last_login_at: DateTime.utc_now() |> DateTime.truncate(:second)
                 }) do
              {:ok, %{id: id}} -> id
              _ -> nil
            end
        end

      %{
        "id" => user_role_id,
        "interactor_user_id" => sub,
        "email" => email,
        "display_name" => display_name,
        "role" => db_role
      }
    else
      _ -> %{"error" => "could_not_extract_user"}
    end
  end

  defp fetch_interactor_profile(user_id, org) do
    with {:ok, app_token} <- FunSheep.Interactor.Auth.get_token(),
         url = "#{interactor_url()}/api/v1/orgs/#{org}/users/#{user_id}",
         {:ok, %{status: 200, body: body}} <-
           Req.get(url, headers: [{"authorization", "Bearer #{app_token}"}]) do
      body
    else
      _ -> %{}
    end
  end

  defp tokens_payload(tokens) do
    %{
      access_token: tokens["access_token"],
      refresh_token: tokens["refresh_token"],
      expires_in: tokens["expires_in"]
    }
  end

  defp user_payload(user) when is_map(user), do: user
  defp user_payload(_), do: %{}

  defp default_mobile_redirect, do: "funsheep://auth/callback"

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp client_id, do: Application.get_env(:fun_sheep, :interactor_client_id, "")
  defp client_secret, do: Application.get_env(:fun_sheep, :interactor_client_secret, "")

  defp maybe_add_idp_hint(query, provider) when provider in ~w(google github apple),
    do: Map.put(query, :idp_hint, provider)

  defp maybe_add_idp_hint(query, _), do: query
end

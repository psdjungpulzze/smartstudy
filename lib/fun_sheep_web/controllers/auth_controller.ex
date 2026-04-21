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

  def root(conn, _params) do
    case get_session(conn, :current_user) do
      nil -> redirect(conn, to: ~p"/auth/login")
      user -> redirect(conn, to: redirect_path_for_role(user["role"]))
    end
  end

  def register(conn, _params) do
    redirect(conn, to: ~p"/auth/register")
  end

  def login(conn, params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32))

    query =
      %{
        client_id: client_id(),
        redirect_uri: callback_url(conn),
        response_type: "code",
        scope: "openid profile email",
        state: state
      }
      |> maybe_add_idp_hint(params["idp_hint"])

    authorize_url =
      interactor_url()
      |> URI.parse()
      |> Map.put(:path, "/oauth/authorize")
      |> URI.append_query(URI.encode_query(query))
      |> URI.to_string()

    conn
    |> put_session(:oauth_state, state)
    |> redirect(external: authorize_url)
  end

  defp maybe_add_idp_hint(query, provider) when provider in ~w(google github apple),
    do: Map.put(query, :idp_hint, provider)

  defp maybe_add_idp_hint(query, _), do: query

  def callback(conn, %{"code" => code, "state" => state}) do
    saved_state = get_session(conn, :oauth_state)

    if state != saved_state do
      conn
      |> put_flash(:error, "Invalid OAuth state. Please try again.")
      |> redirect(to: ~p"/")
    else
      case exchange_code_for_tokens(code, conn) do
        {:ok, tokens} ->
          user = extract_user_from_tokens(tokens, nil)

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

  def session(conn, %{"token" => token} = params) do
    selected_role = params["role"]
    user = extract_user_from_tokens(%{"access_token" => token}, selected_role)

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

  defp extract_user_from_tokens(tokens, selected_role) do
    # The Interactor user JWT contains only: sub, org, username, scopes, type.
    # It does NOT include email or metadata.role, so we fetch the full user
    # record from Interactor's admin API using our M2M (client_credentials) token.
    case decode_jwt(tokens["access_token"]) do
      {:ok, %{"sub" => sub, "org" => org} = claims} ->
        profile = fetch_interactor_user(sub, org)

        email = profile["email"] || claims["username"]
        display_name = profile["username"] || claims["username"] || "User"
        claim_role = get_in(profile, ["metadata", "role"]) || "student"
        role = FunSheep.Accounts.RoleResolver.resolve(claim_role, selected_role)

        user_role_id = ensure_local_user_role(sub, role, email, display_name)

        %{
          "id" => user_role_id || sub,
          "user_role_id" => user_role_id,
          "interactor_user_id" => sub,
          "email" => email,
          "display_name" => display_name,
          "role" => role,
          "org" => org
        }

      _ ->
        %{
          "id" => "unknown",
          "user_role_id" => nil,
          "interactor_user_id" => "unknown",
          "email" => "user@example.com",
          "display_name" => "User",
          "role" => "student"
        }
    end
  end


  defp ensure_local_user_role(interactor_user_id, role, email, display_name) do
    # user_roles.role is an Ecto.Enum [:student, :parent, :teacher, :admin].
    db_role = if role in ~w(student parent teacher admin), do: role, else: "student"

    case FunSheep.Accounts.get_user_role_by_interactor_id_and_role(interactor_user_id, db_role) do
      %FunSheep.Accounts.UserRole{id: id} ->
        id

      nil ->
        case FunSheep.Accounts.create_user_role(%{
               interactor_user_id: interactor_user_id,
               role: db_role,
               email: email || "unknown@example.com",
               display_name: display_name
             }) do
          {:ok, %{id: id}} ->
            id

          {:error, changeset} ->
            Logger.error("Failed to create user_role on login: #{inspect(changeset.errors)}")
            nil
        end
    end
  end

  defp fetch_interactor_user(user_id, org) do
    with {:ok, app_token} <- FunSheep.Interactor.Auth.get_token(),
         url = "#{interactor_url()}/api/v1/orgs/#{org}/users/#{user_id}",
         {:ok, %{status: 200, body: body}} <-
           Req.get(url, headers: [{"authorization", "Bearer #{app_token}"}]) do
      body
    else
      other ->
        Logger.warning("Failed to fetch Interactor user profile: #{inspect(other)}")
        %{}
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

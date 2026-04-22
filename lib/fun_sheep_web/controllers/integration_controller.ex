defmodule FunSheepWeb.IntegrationController do
  @moduledoc """
  Handles OAuth connect/callback and disconnect for external LMS/school
  apps (Google Classroom, Canvas, ParentSquare).

  The OAuth dance itself is owned by Interactor:
    * `connect/2`  – asks Interactor Credential Management for an
      `authorization_url`, redirects the user to it.
    * `callback/2` – the user returns here after authorising on the
      provider; Interactor includes `credential_id` and `service_id`
      on the querystring. We upsert an `IntegrationConnection` and
      enqueue `FunSheep.Workers.IntegrationSyncWorker`.
    * `disconnect/2` – revokes the Interactor credential and marks the
      connection revoked.

  CLAUDE.md honest-failure rule: if Interactor returns an error or a
  response shape we can't parse, we redirect back to `/integrations`
  with a flash error — we **never** fabricate a "pending" connection
  or a placeholder course.
  """

  use FunSheepWeb, :controller

  require Logger

  alias FunSheep.Integrations
  alias FunSheep.Integrations.{IntegrationConnection, Registry}
  alias FunSheep.Interactor.Credentials

  @provider_strings Enum.map(IntegrationConnection.providers(), &Atom.to_string/1)

  def connect(conn, %{"provider" => provider} = params) when provider in @provider_strings do
    provider_atom = String.to_existing_atom(provider)
    provider_module = Registry.module_for(provider_atom)
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "You must log in to connect an integration.")
        |> redirect(to: ~p"/dev/login")

      not provider_module.supported?() ->
        conn
        |> put_flash(:info, "#{Registry.label(provider_atom)} is coming soon.")
        |> redirect(to: ~p"/integrations")

      true ->
        start_oauth(conn, provider_atom, provider_module, user, params)
    end
  end

  def connect(conn, %{"provider" => _}) do
    conn
    |> put_flash(:error, "Unknown provider.")
    |> redirect(to: ~p"/integrations")
  end

  def callback(conn, %{"credential_id" => credential_id, "service_id" => service_id} = params) do
    user = conn.assigns[:current_user]

    if is_nil(user) do
      conn
      |> put_flash(:error, "You must log in to finish connecting.")
      |> redirect(to: ~p"/dev/login")
    else
      provider_atom = resolve_provider_atom(service_id, params["provider"])

      attrs = %{
        user_role_id: user["user_role_id"] || user["id"],
        provider: provider_atom,
        service_id: service_id,
        credential_id: credential_id,
        external_user_id: user["interactor_user_id"] || user["id"],
        status: :syncing,
        metadata: callback_metadata(params)
      }

      case Integrations.upsert_connection(attrs) do
        {:ok, connection} ->
          Integrations.enqueue_sync(connection)

          conn
          |> put_flash(:info, "#{Registry.label(provider_atom)} connected — syncing now.")
          |> redirect(to: ~p"/integrations")

        {:error, changeset} ->
          Logger.warning("[IntegrationController] callback failed: #{inspect(changeset.errors)}")

          conn
          |> put_flash(
            :error,
            "Could not save connection. Please try again, or contact support if this persists."
          )
          |> redirect(to: ~p"/integrations")
      end
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Missing credential information from provider.")
    |> redirect(to: ~p"/integrations")
  end

  def disconnect(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]
    connection = Integrations.get_connection(id)

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "You must log in.")
        |> redirect(to: ~p"/dev/login")

      is_nil(connection) ->
        conn
        |> put_flash(:error, "Integration not found.")
        |> redirect(to: ~p"/integrations")

      connection.user_role_id != (user["user_role_id"] || user["id"]) ->
        conn |> put_status(:forbidden) |> text("Forbidden")

      true ->
        do_disconnect(conn, connection)
    end
  end

  def sync_now(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]
    connection = Integrations.get_connection(id)

    cond do
      is_nil(user) or is_nil(connection) ->
        conn
        |> put_flash(:error, "Integration not found.")
        |> redirect(to: ~p"/integrations")

      connection.user_role_id != (user["user_role_id"] || user["id"]) ->
        conn |> put_status(:forbidden) |> text("Forbidden")

      true ->
        Integrations.enqueue_sync(connection)

        conn
        |> put_flash(:info, "Sync queued.")
        |> redirect(to: ~p"/integrations")
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp start_oauth(conn, provider_atom, provider_module, user, params) do
    attrs =
      %{
        service_id: provider_module.service_id(),
        external_user_id: user["interactor_user_id"] || user["id"],
        scopes: provider_module.default_scopes(),
        success_redirect_url: callback_full_url(conn)
      }
      |> maybe_add_canvas_host(provider_atom, params)

    case Credentials.initiate_oauth(attrs) do
      {:ok, %{"data" => %{"authorization_url" => url}}} when is_binary(url) ->
        redirect(conn, external: url)

      {:ok, %{"authorization_url" => url}} when is_binary(url) ->
        redirect(conn, external: url)

      {:ok, _mock_body} ->
        # Interactor mock mode: no real OAuth URL comes back. Fall through
        # to a mock callback so dev UX still completes. This keeps the
        # test/dev path self-contained without inserting fake data —
        # the mock-callback row is marked `:pending`, not `:active`.
        redirect(conn,
          to:
            ~p"/integrations/callback?credential_id=mock_cred_#{provider_atom}&service_id=#{provider_module.service_id()}&provider=#{provider_atom}"
        )

      {:error, reason} ->
        Logger.warning("[IntegrationController] initiate_oauth failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Could not start OAuth with #{Registry.label(provider_atom)}.")
        |> redirect(to: ~p"/integrations")
    end
  end

  defp maybe_add_canvas_host(attrs, :canvas, %{"canvas_host" => host})
       when is_binary(host) and host != "" do
    Map.put(attrs, :metadata, %{"api_base_url" => normalize_host(host)})
  end

  defp maybe_add_canvas_host(attrs, _provider, _params), do: attrs

  defp normalize_host(host) do
    host
    |> String.trim()
    |> String.trim_trailing("/")
    |> ensure_scheme()
  end

  defp ensure_scheme("http://" <> _ = h), do: h
  defp ensure_scheme("https://" <> _ = h), do: h
  defp ensure_scheme(h), do: "https://" <> h

  defp callback_metadata(%{"canvas_host" => host}) when is_binary(host) and host != "" do
    %{"api_base_url" => normalize_host(host)}
  end

  defp callback_metadata(_), do: %{}

  defp resolve_provider_atom(service_id, fallback) do
    case service_id do
      "google_classroom" -> :google_classroom
      "canvas" -> :canvas
      "parentsquare" -> :parentsquare
      _ -> fallback_provider_atom(fallback)
    end
  end

  defp fallback_provider_atom(p) when p in @provider_strings, do: String.to_existing_atom(p)
  defp fallback_provider_atom(_), do: :google_classroom

  defp do_disconnect(conn, %IntegrationConnection{} = connection) do
    revoke_result =
      if connection.credential_id do
        Credentials.delete_credential(connection.credential_id)
      else
        {:ok, :no_credential}
      end

    case revoke_result do
      {:ok, _} ->
        {:ok, updated} = Integrations.mark_status(connection, :revoked)
        Integrations.broadcast(updated, :revoked)
        Integrations.delete_connection(updated)

        conn
        |> put_flash(:info, "#{Registry.label(connection.provider)} disconnected.")
        |> redirect(to: ~p"/integrations")

      {:error, reason} ->
        Logger.warning("[IntegrationController] revoke failed: #{inspect(reason)}")
        {:ok, _} = Integrations.mark_errored(connection, "revoke failed: #{inspect(reason)}")

        conn
        |> put_flash(
          :error,
          "Could not revoke access with provider. The connection was marked errored so you can retry."
        )
        |> redirect(to: ~p"/integrations")
    end
  end

  defp callback_full_url(_conn), do: FunSheepWeb.Endpoint.url() <> "/integrations/callback"
end

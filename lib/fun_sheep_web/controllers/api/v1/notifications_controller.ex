defmodule FunSheepWeb.API.V1.NotificationsController do
  @moduledoc "Notification list and push token endpoints for the mobile app."

  use FunSheepWeb, :controller

  alias FunSheep.Notifications

  @doc "GET /api/v1/notifications — in-app unread notifications."
  def index(conn, _params) do
    user_role_id = conn.assigns.current_user_role.id
    notifications = Notifications.list_in_app_unread(user_role_id)
    json(conn, %{data: Enum.map(notifications, &notification_payload/1)})
  end

  @doc "POST /api/v1/notifications/:id/read — mark one notification as read."
  def mark_read(conn, %{"id" => notification_id}) do
    user_role_id = conn.assigns.current_user_role.id

    case Notifications.mark_read(user_role_id, notification_id) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  @doc "POST /api/v1/notifications/read-all — mark all notifications as read."
  def mark_all_read(conn, _params) do
    user_role_id = conn.assigns.current_user_role.id
    Notifications.mark_all_read(user_role_id)
    json(conn, %{ok: true})
  end

  @doc """
  POST /api/v1/notifications/push_tokens — register a device push token.

  Body (JSON):
    { "token": "device-token-string", "platform": "ios" | "android" | "web" }
  """
  def register_token(conn, %{"token" => token, "platform" => platform}) do
    user_role_id = conn.assigns.current_user_role.id

    case Notifications.upsert_push_token(user_role_id, token, platform) do
      {:ok, _} ->
        json(conn, %{ok: true})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_token", details: format_errors(changeset)})
    end
  end

  def register_token(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "token and platform are required"})
  end

  @doc "DELETE /api/v1/notifications/push_tokens/:token — deactivate a device token."
  def deactivate_token(conn, %{"token" => token}) do
    Notifications.deactivate_push_token(token)
    json(conn, %{ok: true})
  end

  defp notification_payload(n) do
    %{
      id: n.id,
      type: n.type,
      title: n.title,
      body: n.body,
      action_url: get_in(n.payload, ["action_url"]),
      inserted_at: n.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

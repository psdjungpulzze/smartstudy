defmodule FunSheepWeb.AdminImpersonationController do
  @moduledoc """
  Starts / stops admin impersonation sessions.

  Only reachable by admins (pipe includes `Plugs.RequireAdmin`). The session
  stores the target's user_role_id, the real admin's id, and an expiry.
  LiveViews pick this up via `LiveHelpers` and swap `current_user` while
  preserving the real admin's identity for audit purposes.
  """
  use FunSheepWeb, :controller

  alias FunSheep.{Accounts, Admin}

  def create(conn, %{"user_id" => target_id}) do
    admin = current_admin!(conn)
    target = Accounts.get_user_role!(target_id)

    case Admin.start_impersonation(admin, target) do
      {:ok, session_keys} ->
        conn =
          Enum.reduce(session_keys, conn, fn {k, v}, c -> put_session(c, k, v) end)

        conn
        |> put_flash(:info, "Impersonating #{target.email}. Remember to stop when you're done.")
        |> redirect(to: "/dashboard")

      {:error, reason} ->
        conn
        |> put_flash(:error, humanize_impersonation_error(reason))
        |> redirect(to: ~p"/admin/users")
    end
  end

  def delete(conn, _params) do
    admin = current_admin!(conn)
    target_id = get_session(conn, "impersonated_user_role_id")
    target = target_id && Accounts.get_user_role(target_id)

    if target, do: Admin.stop_impersonation(admin, target, :manual)

    conn
    |> delete_session("impersonated_user_role_id")
    |> delete_session("real_admin_user_role_id")
    |> delete_session("impersonation_expires_at")
    |> put_flash(:info, "Impersonation ended.")
    |> redirect(to: ~p"/admin/users")
  end

  # The admin performing the action. If the conn is already carrying an
  # active impersonation, the "real admin" comes from the impersonation
  # metadata, not the swapped-in user.
  defp current_admin!(conn) do
    real_id = get_session(conn, "real_admin_user_role_id")

    cond do
      is_binary(real_id) and real_id != "" ->
        Accounts.get_user_role!(real_id)

      user = conn.assigns[:current_user] ->
        id = user["user_role_id"] || user["id"]
        Accounts.get_user_role!(id)

      true ->
        raise FunSheepWeb.NotFoundError
    end
  end

  defp humanize_impersonation_error(:cannot_impersonate_self),
    do: "You cannot impersonate yourself."

  defp humanize_impersonation_error(:cannot_impersonate_admin),
    do: "You cannot impersonate another admin."

  defp humanize_impersonation_error(:target_suspended),
    do: "Suspended users cannot be impersonated."

  defp humanize_impersonation_error(:not_admin),
    do: "Only admins can impersonate."

  defp humanize_impersonation_error(reason),
    do: "Unable to start impersonation (#{inspect(reason)})."
end

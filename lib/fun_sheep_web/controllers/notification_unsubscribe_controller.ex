defmodule FunSheepWeb.NotificationUnsubscribeController do
  @moduledoc """
  No-auth unsubscribe endpoint backing the signed token in the weekly
  digest email (spec §8.4).

  Flipping `digest_frequency` to `:off` on a valid token suffices — the
  scheduler skips `:off` recipients on its next run. Invalid or expired
  tokens render a generic message so we don't leak whether a guardian
  exists.
  """

  use FunSheepWeb, :controller

  alias FunSheep.{Accounts, Repo}
  alias FunSheep.Accounts.UserRole
  alias FunSheep.Notifications.UnsubscribeToken

  def show(conn, %{"token" => token}) do
    case UnsubscribeToken.verify(token) do
      {:ok, guardian_id} ->
        with %UserRole{} = guardian <- Accounts.get_user_role(guardian_id),
             {:ok, _} <-
               guardian
               |> UserRole.changeset(%{digest_frequency: :off})
               |> Repo.update() do
          send_resp(
            conn,
            200,
            "You've been unsubscribed from the weekly parent digest. " <>
              "You can turn it back on anytime at /parent/settings."
          )
        else
          _ -> send_resp(conn, 200, "You're already unsubscribed.")
        end

      _ ->
        send_resp(
          conn,
          200,
          "That link isn't valid anymore. Open /parent/settings to manage your preferences."
        )
    end
  end
end

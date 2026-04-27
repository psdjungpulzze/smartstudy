defmodule FunSheepWeb.API.V1.UsersController do
  @moduledoc "Current user profile endpoints for the mobile app."

  use FunSheepWeb, :controller

  alias FunSheep.Accounts

  @doc "GET /api/v1/users/me"
  def me(conn, _params) do
    user_role = conn.assigns.current_user_role
    json(conn, %{data: user_payload(user_role)})
  end

  @doc "PUT /api/v1/users/me — update display_name, timezone, notification preferences."
  def update(conn, params) do
    user_role = conn.assigns.current_user_role

    allowed = ~w(
      display_name timezone grade gender
      push_enabled digest_frequency
      alerts_skipped_days alerts_readiness_drop alerts_goal_achieved
      notification_quiet_start notification_quiet_end
    )

    attrs = Map.take(params, allowed)

    case Accounts.update_user_role(user_role, attrs) do
      {:ok, updated} ->
        json(conn, %{data: user_payload(updated)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  defp user_payload(user_role) do
    %{
      id: user_role.id,
      display_name: user_role.display_name,
      email: user_role.email,
      role: user_role.role,
      grade: user_role.grade,
      timezone: user_role.timezone,
      push_enabled: user_role.push_enabled,
      digest_frequency: user_role.digest_frequency,
      notification_quiet_start: user_role.notification_quiet_start,
      notification_quiet_end: user_role.notification_quiet_end,
      onboarding_complete: not is_nil(user_role.onboarding_completed_at)
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

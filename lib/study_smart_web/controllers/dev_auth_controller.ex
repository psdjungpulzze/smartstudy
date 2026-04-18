defmodule StudySmartWeb.DevAuthController do
  use StudySmartWeb, :controller

  # Deterministic UUIDs for dev roles so sessions are consistent
  @dev_uuids %{
    "student" => "00000000-0000-4000-a000-000000000001",
    "parent" => "00000000-0000-4000-a000-000000000002",
    "teacher" => "00000000-0000-4000-a000-000000000003",
    "admin" => "00000000-0000-4000-a000-000000000004"
  }

  def create(conn, %{"role" => role}) do
    dev_id = Map.get(@dev_uuids, role, Ecto.UUID.generate())

    user = %{
      "id" => dev_id,
      "user_role_id" => dev_id,
      "role" => role,
      "email" => "dev_#{role}@studysmart.test",
      "display_name" => "Dev #{String.capitalize(role)}",
      "interactor_user_id" => "dev_interactor_#{role}"
    }

    conn
    |> put_session(:dev_user_id, user["id"])
    |> put_session(:dev_user, user)
    |> redirect(to: redirect_path(role))
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/dev/login")
  end

  defp redirect_path("student"), do: "/dashboard"
  defp redirect_path("parent"), do: "/parent"
  defp redirect_path("teacher"), do: "/teacher"
  defp redirect_path("admin"), do: "/admin"
  defp redirect_path(_), do: "/dashboard"
end

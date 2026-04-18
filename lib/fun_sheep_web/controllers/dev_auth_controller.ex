defmodule FunSheepWeb.DevAuthController do
  use FunSheepWeb, :controller

  alias FunSheep.Accounts

  # Deterministic UUIDs for dev roles so sessions are consistent
  @dev_uuids %{
    "student" => "00000000-0000-4000-a000-000000000001",
    "parent" => "00000000-0000-4000-a000-000000000002",
    "teacher" => "00000000-0000-4000-a000-000000000003",
    "admin" => "00000000-0000-4000-a000-000000000004"
  }

  def create(conn, %{"role" => role}) do
    _dev_id = Map.get(@dev_uuids, role, Ecto.UUID.generate())
    interactor_id = "dev_interactor_#{role}"
    email = "dev_#{role}@studysmart.test"
    display_name = "Dev #{String.capitalize(role)}"

    # Ensure a user_role record exists in the DB
    user_role = ensure_user_role(interactor_id, role, email, display_name)

    user = %{
      "id" => user_role.id,
      "user_role_id" => user_role.id,
      "role" => role,
      "email" => email,
      "display_name" => display_name,
      "interactor_user_id" => interactor_id
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

  defp ensure_user_role(interactor_id, role, email, display_name) do
    # The user_roles table only supports student/parent/teacher roles.
    # Admin is a special dev-only role that maps to "student" in the DB.
    db_role = if role in ~w(student parent teacher), do: role, else: "student"

    case Accounts.get_user_role_by_interactor_id(interactor_id) do
      nil ->
        {:ok, ur} =
          Accounts.create_user_role(%{
            interactor_user_id: interactor_id,
            role: db_role,
            email: email,
            display_name: display_name
          })

        ur

      existing ->
        existing
    end
  end

  defp redirect_path("student"), do: "/dashboard"
  defp redirect_path("parent"), do: "/parent"
  defp redirect_path("teacher"), do: "/teacher"
  defp redirect_path("admin"), do: "/admin"
  defp redirect_path(_), do: "/dashboard"
end

defmodule StudySmartWeb.DevAuthController do
  use StudySmartWeb, :controller

  def create(conn, %{"role" => role}) do
    user = %{
      "id" => "dev_#{role}_#{:rand.uniform(1000)}",
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

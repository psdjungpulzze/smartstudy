defmodule StudySmartWeb.PageController do
  use StudySmartWeb, :controller

  def home(conn, _params) do
    cond do
      get_session(conn, :current_user) ->
        user = get_session(conn, :current_user)
        redirect(conn, to: redirect_path(user["role"]))

      get_session(conn, :dev_user_id) ->
        user = get_session(conn, :dev_user)
        redirect(conn, to: redirect_path(user["role"]))

      true ->
        redirect(conn, to: "/auth/login")
    end
  end

  defp redirect_path("parent"), do: "/parent"
  defp redirect_path("teacher"), do: "/teacher"
  defp redirect_path("admin"), do: "/admin"
  defp redirect_path(_), do: "/dashboard"
end

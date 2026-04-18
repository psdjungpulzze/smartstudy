defmodule StudySmartWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for authentication and common assigns.
  Supports both real Interactor auth and dev auth bypass.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_auth, _params, session, socket) do
    case get_user_from_session(session) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, user["role"])
          |> assign(:current_path, nil)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

        {:cont, socket}

      :not_authenticated ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: login_path())

        {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case get_user_from_session(session) do
      {:ok, %{"role" => "admin"} = user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, "admin")
          |> assign(:current_path, nil)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

        {:cont, socket}

      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:error, "You do not have admin access.")
          |> redirect(to: "/dashboard")

        {:halt, socket}

      :not_authenticated ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: login_path())

        {:halt, socket}
    end
  end

  # Check real auth first, then fall back to dev auth
  defp get_user_from_session(%{"current_user" => user}) when is_map(user) do
    {:ok, user}
  end

  defp get_user_from_session(%{"dev_user" => user, "dev_user_id" => _id}) do
    {:ok, user}
  end

  defp get_user_from_session(_), do: :not_authenticated

  defp login_path do
    if Application.get_env(:study_smart, :dev_routes) do
      "/dev/login"
    else
      "/"
    end
  end

  defp save_request_path(_params, url, socket) do
    uri = URI.parse(url)
    {:cont, assign(socket, :current_path, uri.path)}
  end
end

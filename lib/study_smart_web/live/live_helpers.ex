defmodule StudySmartWeb.LiveHelpers do
  @moduledoc """
  LiveView on_mount hooks for authentication and common assigns.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_auth, _params, session, socket) do
    case session do
      %{"dev_user" => user, "dev_user_id" => _id} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, user["role"])
          |> assign(:current_path, nil)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

        {:cont, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/dev/login")

        {:halt, socket}
    end
  end

  def on_mount(:require_admin, _params, session, socket) do
    case session do
      %{"dev_user" => %{"role" => "admin"} = user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:current_role, "admin")
          |> assign(:current_path, nil)
          |> attach_hook(:save_request_path, :handle_params, &save_request_path/3)

        {:cont, socket}

      %{"dev_user" => _user} ->
        socket =
          socket
          |> put_flash(:error, "You do not have admin access.")
          |> redirect(to: "/dashboard")

        {:halt, socket}

      _ ->
        socket =
          socket
          |> put_flash(:error, "You must log in to access this page.")
          |> redirect(to: "/dev/login")

        {:halt, socket}
    end
  end

  defp save_request_path(_params, url, socket) do
    uri = URI.parse(url)
    {:cont, assign(socket, :current_path, uri.path)}
  end
end

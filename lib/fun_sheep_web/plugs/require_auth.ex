defmodule FunSheepWeb.Plugs.RequireAuth do
  @moduledoc """
  Redirects unauthenticated users to the dev login page.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/dev/login")
      |> halt()
    end
  end
end

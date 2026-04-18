defmodule StudySmartWeb.Plugs.RequireAdmin do
  @moduledoc """
  Requires the current user to have the admin role.
  Redirects to dashboard if not an admin.
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_role] == "admin" do
      conn
    else
      conn
      |> put_flash(:error, "You do not have admin access.")
      |> redirect(to: "/dashboard")
      |> halt()
    end
  end
end

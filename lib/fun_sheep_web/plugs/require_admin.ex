defmodule FunSheepWeb.Plugs.RequireAdmin do
  @moduledoc """
  Requires the current user to have the admin role.

  Raises `FunSheepWeb.NotFoundError` when the current user is not an admin,
  so that admin routes are indistinguishable from non-existent routes to
  unauthorized users. This avoids fingerprinting the admin surface.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_role] == "admin" do
      conn
    else
      raise FunSheepWeb.NotFoundError
    end
  end
end

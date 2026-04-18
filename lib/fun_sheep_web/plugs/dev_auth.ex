defmodule FunSheepWeb.Plugs.DevAuth do
  @moduledoc """
  Authentication plug that checks both real Interactor auth and dev bypass.
  Real auth (current_user in session) takes precedence over dev auth.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      # Real Interactor auth
      user = get_session(conn, :current_user) ->
        conn
        |> assign(:current_user, user)
        |> assign(:current_role, user["role"])

      # Dev auth bypass
      get_session(conn, :dev_user_id) ->
        user = get_session(conn, :dev_user)

        conn
        |> assign(:current_user, user)
        |> assign(:current_role, user["role"])

      true ->
        conn
    end
  end
end

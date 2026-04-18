defmodule StudySmartWeb.Plugs.DevAuth do
  @moduledoc """
  Development-only authentication bypass.
  Allows selecting a role (student/parent/teacher/admin) without Interactor.
  Only active when `config :study_smart, dev_routes: true`.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, :dev_user_id) do
      user = get_session(conn, :dev_user)

      conn
      |> assign(:current_user, user)
      |> assign(:current_role, user["role"])
    else
      conn
    end
  end
end

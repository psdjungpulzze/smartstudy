defmodule FunSheepWeb.HealthController do
  use FunSheepWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end

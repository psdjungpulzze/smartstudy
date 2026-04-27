defmodule FunSheepWeb.HealthController do
  use FunSheepWeb, :controller

  def index(conn, _params) do
    case Ecto.Adapters.SQL.query(FunSheep.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "degraded", reason: "db_unreachable"})
    end
  end
end

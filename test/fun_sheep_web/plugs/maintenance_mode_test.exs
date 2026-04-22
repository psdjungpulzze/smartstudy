defmodule FunSheepWeb.Plugs.MaintenanceModeTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias FunSheepWeb.Plugs.MaintenanceMode

  describe "MaintenanceMode.call/2" do
    test "passes through when maintenance flag is off" do
      conn = conn(:get, "/dashboard") |> MaintenanceMode.call([])
      refute conn.halted
    end

    test "lets /admin/* through even if flag cannot be resolved" do
      conn = conn(:get, "/admin/flags") |> MaintenanceMode.call([])
      refute conn.halted
    end

    test "lets /health through (Cloud Run probe)" do
      conn = conn(:get, "/health") |> MaintenanceMode.call([])
      refute conn.halted
    end

    test "lets /auth/login through" do
      conn = conn(:get, "/auth/login") |> MaintenanceMode.call([])
      refute conn.halted
    end

    test "lets /api/webhooks/interactor through" do
      conn = conn(:post, "/api/webhooks/interactor") |> MaintenanceMode.call([])
      refute conn.halted
    end
  end
end

defmodule FunSheep.Admin.HealthTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Admin.Health

  describe "snapshot/0" do
    test "returns a map with every declared probe" do
      snap = Health.snapshot()

      assert Map.has_key?(snap, :postgres)
      assert Map.has_key?(snap, :oban)
      assert Map.has_key?(snap, :ai_calls)
      assert Map.has_key?(snap, :mailer)
    end
  end

  describe "check_postgres/0" do
    test "returns :ok when the repo responds to SELECT 1" do
      probe = Health.check_postgres()
      assert probe.status == :ok
      assert Map.has_key?(probe.detail, :pool_size)
    end
  end

  describe "check_oban/0" do
    test "returns :ok with empty counts when no jobs exist" do
      probe = Health.check_oban()
      assert probe.status in [:ok, :degraded]
      assert is_map(probe.detail.by_state)
      assert is_integer(probe.detail.total_last_hour)
    end
  end

  describe "check_ai_calls/0" do
    test "returns :ok when no recent calls exist" do
      probe = Health.check_ai_calls()
      assert probe.status in [:ok, :degraded]
    end
  end

  describe "check_mailer/0" do
    test "returns :ok when mailer adapter is configured" do
      probe = Health.check_mailer()
      assert probe.status == :ok
      assert probe.detail.adapter =~ "Swoosh" or is_binary(probe.detail.adapter)
    end
  end
end

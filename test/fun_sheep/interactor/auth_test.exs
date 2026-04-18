defmodule FunSheep.Interactor.AuthTest do
  use ExUnit.Case, async: true

  alias FunSheep.Interactor.Auth

  describe "get_token/0 in mock mode" do
    test "returns a mock token" do
      assert {:ok, "mock_interactor_token"} = Auth.get_token()
    end

    test "returns the same mock token on repeated calls" do
      assert {:ok, token1} = Auth.get_token()
      assert {:ok, token2} = Auth.get_token()
      assert token1 == token2
    end
  end

  describe "GenServer state" do
    test "starts successfully" do
      name = :"auth_test_#{:rand.uniform(100_000)}"
      assert {:ok, pid} = GenServer.start_link(Auth, [], name: name)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "initial state has nil token" do
      name = :"auth_test_#{:rand.uniform(100_000)}"
      {:ok, pid} = GenServer.start_link(Auth, [], name: name)
      state = :sys.get_state(pid)
      assert state.token == nil
      assert state.expires_at == nil
      GenServer.stop(pid)
    end
  end
end

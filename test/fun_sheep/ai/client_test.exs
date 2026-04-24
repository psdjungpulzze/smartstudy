defmodule FunSheep.AI.ClientTest do
  use ExUnit.Case, async: true
  import Mox

  alias FunSheep.AI.ClientMock

  setup :verify_on_exit!

  setup do
    Application.put_env(:fun_sheep, :ai_client_impl, FunSheep.AI.ClientMock)
    on_exit(fn -> Application.delete_env(:fun_sheep, :ai_client_impl) end)
    :ok
  end

  defp client, do: Application.get_env(:fun_sheep, :ai_client_impl, FunSheep.AI.Client)

  test "dispatches through mock when ai_client_impl is set" do
    expect(ClientMock, :call, fn "sys", "usr", %{model: "claude-haiku-4-5-20251001"} ->
      {:ok, "mocked"}
    end)

    assert {:ok, "mocked"} =
             client().call("sys", "usr", %{model: "claude-haiku-4-5-20251001", max_tokens: 100})
  end

  describe "FunSheep.AI.Client.call/3 provider routing" do
    test "module loads and satisfies the behaviour" do
      assert {:module, FunSheep.AI.Client} = Code.ensure_loaded(FunSheep.AI.Client)
      assert function_exported?(FunSheep.AI.Client, :call, 3)
    end
  end
end

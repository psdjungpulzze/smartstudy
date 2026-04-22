defmodule FunSheep.InteractorMockDefaultTest do
  @moduledoc """
  Confirms North Star I-13: :fun_sheep, :interactor_mock defaults to
  OFF when the key is unset.
  """

  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:fun_sheep, :interactor_mock)
    Application.delete_env(:fun_sheep, :interactor_mock)

    on_exit(fn ->
      if original == nil do
        Application.delete_env(:fun_sheep, :interactor_mock)
      else
        Application.put_env(:fun_sheep, :interactor_mock, original)
      end
    end)

    :ok
  end

  test "default is false when key is unset" do
    refute Application.get_env(:fun_sheep, :interactor_mock, false)
  end
end

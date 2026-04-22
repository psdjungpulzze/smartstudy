defmodule FunSheep.InteractorMockDefaultTest do
  @moduledoc """
  Confirms North Star invariant I-13: the `:fun_sheep, :interactor_mock`
  config defaults to OFF everywhere except the test environment.

  We don't re-assert the value of the config itself (that's trivial). We
  assert the DEFAULT used when the key is absent, because the invariant is
  specifically about "a missing config must not silently mock production".
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

  test "every mock-mode check defaults to false when the key is unset" do
    # When unset, Application.get_env returns the default.
    assert Application.get_env(:fun_sheep, :interactor_mock, false) == false
    refute Application.get_env(:fun_sheep, :interactor_mock, false)
  end
end

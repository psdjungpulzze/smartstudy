defmodule FunSheep.Interactor.AgentRegistryTest do
  use ExUnit.Case, async: true

  alias FunSheep.Interactor.AgentRegistry

  describe "list/1 in mock mode" do
    test "returns one row per default spec and tags them :missing" do
      # In test env Interactor is mocked; list_assistants returns empty so
      # no live row matches any intended name → status :missing.
      rows = AgentRegistry.list()

      assert length(rows) == length(AgentRegistry.default_specs())
      assert Enum.all?(rows, &Map.has_key?(&1, :intended_model))
      assert Enum.all?(rows, &(&1.status in [:missing, :unreachable]))
    end

    test "includes the expected default modules" do
      rows = AgentRegistry.list()
      modules = Enum.map(rows, & &1.module)
      assert FunSheep.Tutor in modules
      assert FunSheep.Questions.Validation in modules
    end

    test "lifts intended_model from the module's assistant_attrs/0" do
      rows = AgentRegistry.list()
      tutor_row = Enum.find(rows, &(&1.module == FunSheep.Tutor))
      assert tutor_row.intended_model == "gpt-4o"
      assert is_binary(tutor_row.name)
    end
  end

  describe "implements_spec?/1" do
    test "returns true for modules that declare the behaviour" do
      assert AgentRegistry.implements_spec?(FunSheep.Tutor)
      assert AgentRegistry.implements_spec?(FunSheep.Questions.Validation)
    end

    test "returns false for unrelated modules" do
      refute AgentRegistry.implements_spec?(FunSheep.Repo)
      refute AgentRegistry.implements_spec?(:not_a_module)
    end
  end
end

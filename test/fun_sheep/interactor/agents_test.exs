defmodule FunSheep.Interactor.AgentsTest do
  use ExUnit.Case, async: true

  alias FunSheep.Interactor.Agents

  describe "create_assistant/1 in mock mode" do
    test "returns mock data with an ID" do
      attrs = %{name: "Test Agent", model: "gpt-4o", system_prompt: "You are a test agent."}
      assert {:ok, %{"data" => data}} = Agents.create_assistant(attrs)
      assert is_binary(data["id"])
      assert String.starts_with?(data["id"], "mock_")
    end
  end

  describe "list_assistants/0 in mock mode" do
    test "returns empty data list" do
      assert {:ok, %{"data" => []}} = Agents.list_assistants()
    end
  end

  describe "create_room/3 in mock mode" do
    test "returns mock data" do
      assert {:ok, %{"data" => data}} = Agents.create_room("asst_1", "user_123", %{course: "bio"})
      assert is_binary(data["id"])
    end
  end

  describe "send_message/3 in mock mode" do
    test "returns mock data with content" do
      assert {:ok, %{"data" => data}} = Agents.send_message("room_1", "Hello!")
      assert data["content"] == "Hello!"
    end
  end

  describe "list_messages/1 in mock mode" do
    test "returns empty data list" do
      assert {:ok, %{"data" => []}} = Agents.list_messages("room_1")
    end
  end

  describe "resolve_or_create_assistant/1 in mock mode" do
    test "creates-and-caches when not found in the list" do
      # Each test uses a fresh name so cache lookups across tests don't leak.
      name = "resolve_create_#{System.unique_integer([:positive])}"
      attrs = %{name: name, llm_provider: "openai", llm_model: "gpt-4o-mini"}

      assert {:ok, id} = Agents.resolve_or_create_assistant(attrs)
      assert is_binary(id)
    end

    test "returns the cached id on a second call without re-creating" do
      name = "resolve_create_#{System.unique_integer([:positive])}"
      attrs = %{name: name, llm_provider: "openai", llm_model: "gpt-4o-mini"}

      {:ok, id1} = Agents.resolve_or_create_assistant(attrs)
      {:ok, id2} = Agents.resolve_or_create_assistant(attrs)

      assert id1 == id2
    end
  end
end

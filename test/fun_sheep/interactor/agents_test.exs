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
end

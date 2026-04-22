defmodule FunSheep.Interactor.ServiceKnowledgeBaseTest do
  use ExUnit.Case, async: true

  alias FunSheep.Interactor.ServiceKnowledgeBase

  describe "get_service/1 (mock mode)" do
    test "returns google_classroom definition with scopes" do
      assert {:ok, %{"data" => svc}} = ServiceKnowledgeBase.get_service("google_classroom")
      assert svc["slug"] == "google_classroom"
      assert svc["api_base_url"] == "https://classroom.googleapis.com"

      assert "https://www.googleapis.com/auth/classroom.courses.readonly" in svc["default_scopes"]
    end

    test "returns canvas definition" do
      assert {:ok, %{"data" => svc}} = ServiceKnowledgeBase.get_service("canvas")
      assert svc["slug"] == "canvas"
      assert svc["default_scopes"] != []
    end

    test "returns a generic payload for unknown slugs" do
      assert {:ok, %{"data" => svc}} = ServiceKnowledgeBase.get_service("unknown_service")
      assert svc["slug"] == "unknown_service"
    end
  end

  describe "list_capabilities/1 and search_services/1" do
    test "return empty lists in mock mode" do
      assert {:ok, %{"data" => []}} = ServiceKnowledgeBase.list_capabilities("google_classroom")

      assert {:ok, %{"data" => [], "total" => 0}} =
               ServiceKnowledgeBase.search_services(%{q: "lms"})
    end
  end
end

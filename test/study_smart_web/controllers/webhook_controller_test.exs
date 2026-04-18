defmodule StudySmartWeb.WebhookControllerTest do
  use StudySmartWeb.ConnCase, async: true

  describe "POST /api/webhooks/interactor" do
    test "receives agent.response_sent events", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/interactor", %{type: "agent.response_sent", data: %{}})

      assert json_response(conn, 200)["status"] == "received"
    end

    test "receives workflow events", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/interactor", %{type: "workflow.state_changed", data: %{}})

      assert json_response(conn, 200)["status"] == "received"
    end

    test "receives credential events", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/interactor", %{type: "credential.expired", data: %{}})

      assert json_response(conn, 200)["status"] == "received"
    end

    test "handles unknown event types gracefully", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/interactor", %{type: "unknown.event", data: %{}})

      assert json_response(conn, 200)["status"] == "received"
    end
  end

  describe "POST /api/webhooks/agent-tools" do
    test "returns 404 for unknown tool", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{tool_name: "nonexistent_tool"})

      assert json_response(conn, 404)["error"] == "Unknown tool"
    end

    test "returns 400 when tool_name is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{})

      assert json_response(conn, 400)["error"] == "Missing tool_name"
    end

    test "get_ocr_text returns error for non-existent material", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{
          tool_name: "get_ocr_text",
          arguments: %{material_id: fake_id}
        })

      assert json_response(conn, 200)["error"] == "Material not found"
    end

    test "get_ocr_text returns 400 when arguments missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{tool_name: "get_ocr_text"})

      assert json_response(conn, 400)["error"] =~ "Missing"
    end

    test "search_questions returns empty list for non-existent course", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{
          tool_name: "search_questions",
          arguments: %{course_id: fake_id}
        })

      assert json_response(conn, 200)["questions"] == []
    end

    test "store_question returns validation errors for invalid data", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/agent-tools", %{
          tool_name: "store_question",
          arguments: %{}
        })

      assert json_response(conn, 422)["errors"]
    end
  end
end

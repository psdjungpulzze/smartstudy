defmodule FunSheep.Search.TavilyClientTest do
  use ExUnit.Case, async: true

  alias FunSheep.Search.TavilyClient

  setup do
    Application.put_env(:fun_sheep, :tavily_api_key, "tvly-test-key")
    Application.put_env(:fun_sheep, :tavily_req_opts, plug: {Req.Test, TavilyClient})

    on_exit(fn ->
      Application.put_env(:fun_sheep, :tavily_api_key, nil)
      Application.delete_env(:fun_sheep, :tavily_req_opts)
    end)

    :ok
  end

  describe "search/2 — success" do
    test "returns parsed results on HTTP 200" do
      Req.Test.stub(TavilyClient, fn conn ->
        Req.Test.json(conn, %{
          "query" => "SAT math practice questions",
          "results" => [
            %{
              "title" => "Khan Academy SAT Math Practice",
              "url" => "https://www.khanacademy.org/sat-math",
              "content" => "Practice SAT math problems covering algebra and geometry.",
              "score" => 0.95
            },
            %{
              "title" => "College Board Official SAT Practice",
              "url" => "https://collegeboard.org/sat/practice",
              "content" => "Official practice tests from College Board.",
              "score" => 0.91
            }
          ]
        })
      end)

      assert {:ok, results} = TavilyClient.search("SAT math practice questions")
      assert length(results) == 2

      [first | _] = results
      assert first.title == "Khan Academy SAT Math Practice"
      assert first.url == "https://www.khanacademy.org/sat-math"
      assert first.snippet == "Practice SAT math problems covering algebra and geometry."
      assert first.publisher == "khanacademy.org"
      assert first.confidence == 0.95
    end

    test "strips www. prefix from publisher" do
      Req.Test.stub(TavilyClient, fn conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{"title" => "T", "url" => "https://www.example.com/page", "content" => "c", "score" => 0.8}
          ]
        })
      end)

      assert {:ok, [result]} = TavilyClient.search("anything")
      assert result.publisher == "example.com"
    end

    test "uses 0.8 confidence when score is missing" do
      Req.Test.stub(TavilyClient, fn conn ->
        Req.Test.json(conn, %{
          "results" => [
            %{"title" => "T", "url" => "https://example.com", "content" => "c"}
          ]
        })
      end)

      assert {:ok, [result]} = TavilyClient.search("anything")
      assert result.confidence == 0.8
    end

    test "returns error when results key is missing from 200 response" do
      Req.Test.stub(TavilyClient, fn conn ->
        Req.Test.json(conn, %{"query" => "q"})
      end)

      assert {:error, :unexpected_response} = TavilyClient.search("no results key")
    end
  end

  describe "search/2 — HTTP errors" do
    test "returns :rate_limited on 429" do
      Req.Test.stub(TavilyClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(429, ~s({"error":"rate limit exceeded"}))
      end)

      assert {:error, :rate_limited} = TavilyClient.search("query")
    end

    test "returns {:error, {:http_status, status}} on non-200 non-429" do
      Req.Test.stub(TavilyClient, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, ~s({"error":"unauthorized"}))
      end)

      assert {:error, {:http_status, 401}} = TavilyClient.search("query")
    end
  end

  describe "search/2 — missing API key" do
    test "returns :no_api_key when key is not configured" do
      Application.put_env(:fun_sheep, :tavily_api_key, nil)
      assert {:error, :no_api_key} = TavilyClient.search("query")
    end

    test "returns :no_api_key when key is empty string" do
      Application.put_env(:fun_sheep, :tavily_api_key, "")
      assert {:error, :no_api_key} = TavilyClient.search("query")
    end
  end
end

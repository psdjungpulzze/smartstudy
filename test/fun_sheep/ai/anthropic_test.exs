defmodule FunSheep.AI.AnthropicTest do
  use ExUnit.Case, async: true

  alias FunSheep.AI.Anthropic

  @opts %{model: "claude-haiku-4-5-20251001", max_tokens: 100, source: "test"}

  defp stub(status, body) do
    Req.Test.stub(FunSheep.AI.Anthropic, fn conn ->
      Req.Test.json(conn, body) |> Map.put(:status, status)
    end)
  end

  describe "200 success" do
    test "extracts text from a well-formed response" do
      stub(200, %{"content" => [%{"type" => "text", "text" => "The answer is 42"}]})
      assert {:ok, "The answer is 42"} = Anthropic.call("sys", "usr", @opts)
    end

    test "extracts the first content block when multiple are present" do
      stub(200, %{
        "content" => [
          %{"type" => "text", "text" => "First"},
          %{"type" => "text", "text" => "Second"}
        ]
      })

      assert {:ok, "First"} = Anthropic.call("sys", "usr", @opts)
    end
  end

  describe "error handling" do
    test "returns {:error, :rate_limited} after exhausting retries on 429" do
      # max_retries = 3, so 4 total calls all return 429
      Req.Test.expect(FunSheep.AI.Anthropic, 4, fn conn ->
        Req.Test.json(conn, %{"error" => "rate limited"}) |> Map.put(:status, 429)
      end)

      assert {:error, :rate_limited} = Anthropic.call("sys", "usr", @opts)
    end

    test "returns error tuple on non-200/non-retryable status" do
      stub(400, %{"error" => %{"message" => "Bad request"}})

      assert {:error, {400, %{"error" => %{"message" => "Bad request"}}}} =
               Anthropic.call("sys", "usr", @opts)
    end

    test "returns {:error, {:unexpected_response, body}} for malformed 200" do
      stub(200, %{"unexpected" => "format"})
      assert {:error, {:unexpected_response, _}} = Anthropic.call("sys", "usr", @opts)
    end

    test "returns {:error, {:unexpected_content, content}} for non-text content type" do
      stub(200, %{"content" => [%{"type" => "tool_use", "id" => "abc"}]})
      assert {:error, {:unexpected_content, _}} = Anthropic.call("sys", "usr", @opts)
    end

    test "returns {:error, :overloaded} after exhausting retries on 529" do
      Req.Test.expect(FunSheep.AI.Anthropic, 4, fn conn ->
        Req.Test.json(conn, %{"error" => "overloaded"}) |> Map.put(:status, 529)
      end)

      assert {:error, :overloaded} = Anthropic.call("sys", "usr", @opts)
    end
  end
end

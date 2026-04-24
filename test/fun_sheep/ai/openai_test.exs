defmodule FunSheep.AI.OpenAITest do
  use ExUnit.Case, async: true

  alias FunSheep.AI.OpenAI

  @opts %{model: "gpt-4o-mini", max_tokens: 100, source: "test"}

  defp stub(status, body) do
    Req.Test.stub(FunSheep.AI.OpenAI, fn conn ->
      Req.Test.json(conn, body) |> Map.put(:status, status)
    end)
  end

  describe "200 success" do
    test "extracts text from a well-formed response" do
      stub(200, %{"choices" => [%{"message" => %{"content" => "The answer is 42"}}]})
      assert {:ok, "The answer is 42"} = OpenAI.call("sys", "usr", @opts)
    end

    test "extracts the first choice when multiple are present" do
      stub(200, %{
        "choices" => [
          %{"message" => %{"content" => "First"}},
          %{"message" => %{"content" => "Second"}}
        ]
      })

      assert {:ok, "First"} = OpenAI.call("sys", "usr", @opts)
    end
  end

  describe "error handling" do
    test "returns {:error, :rate_limited} after exhausting retries on 429" do
      # max_retries = 3, so 4 total calls all return 429
      Req.Test.expect(FunSheep.AI.OpenAI, 4, fn conn ->
        Req.Test.json(conn, %{"error" => "rate limited"}) |> Map.put(:status, 429)
      end)

      assert {:error, :rate_limited} = OpenAI.call("sys", "usr", @opts)
    end

    test "returns error tuple on non-200/non-retryable status" do
      stub(400, %{"error" => %{"message" => "Bad request"}})

      assert {:error, {400, %{"error" => %{"message" => "Bad request"}}}} =
               OpenAI.call("sys", "usr", @opts)
    end

    test "returns {:error, {:unexpected_response, body}} for malformed 200" do
      stub(200, %{"unexpected" => "format"})
      assert {:error, {:unexpected_response, _}} = OpenAI.call("sys", "usr", @opts)
    end

    test "returns {:error, {:unexpected_choices, []}} for empty choices" do
      stub(200, %{"choices" => []})
      assert {:error, {:unexpected_choices, []}} = OpenAI.call("sys", "usr", @opts)
    end
  end
end

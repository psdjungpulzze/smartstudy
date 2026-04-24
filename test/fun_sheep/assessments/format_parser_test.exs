defmodule FunSheep.Assessments.FormatParserTest do
  use ExUnit.Case, async: true
  import Mox

  alias FunSheep.AI.ClientMock
  alias FunSheep.Assessments.FormatParser

  setup :verify_on_exit!

  describe "parse/1" do
    test "returns error for empty input" do
      assert {:error, :empty_input} = FormatParser.parse("")
      assert {:error, :empty_input} = FormatParser.parse(nil)
    end

    test "parses a well-formed LLM response" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "format_parser"} ->
        {:ok,
         ~S({
           "sections": [
             {"name": "Multiple Choice", "question_type": "multiple_choice", "count": 20, "points_per_question": 1, "time_minutes": 30},
             {"name": "FRQ", "question_type": "free_response", "count": 3, "points_per_question": 5, "time_minutes": 35}
           ],
           "time_limit_minutes": 65
         })}
      end)

      assert {:ok, result} = FormatParser.parse("20 MC (30 min)\nFRQ: 3 - 5pt questions (35 min)")
      assert length(result.sections) == 2
      assert result.time_limit_minutes == 65

      [mc, frq] = result.sections
      assert mc["question_type"] == "multiple_choice"
      assert mc["count"] == 20
      assert frq["question_type"] == "free_response"
      assert frq["count"] == 3
    end

    test "normalizes invalid question types to multiple_choice" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"sections":[{"name":"S1","question_type":"essay","count":5,"points_per_question":2}],"time_limit_minutes":null})}
      end)

      assert {:ok, %{sections: [section]}} = FormatParser.parse("5 essay questions")
      assert section["question_type"] == "multiple_choice"
    end

    test "strips markdown fences from response" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         "```json\n{\"sections\":[{\"name\":\"MC\",\"question_type\":\"multiple_choice\",\"count\":10,\"points_per_question\":1}],\"time_limit_minutes\":null}\n```"}
      end)

      assert {:ok, %{sections: [_]}} = FormatParser.parse("10 MC")
    end

    test "returns error when LLM call fails" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} = FormatParser.parse("20 questions")
    end

    test "returns error when LLM response is not valid JSON" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, "I cannot parse that format."}
      end)

      assert {:error, :invalid_json} = FormatParser.parse("something weird")
    end

    test "returns error when sections key is missing" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"time_limit_minutes": 60})}
      end)

      assert {:error, :unexpected_shape} = FormatParser.parse("some format")
    end

    test "each section always has chapter_ids: []" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         ~S({"sections":[{"name":"SA","question_type":"short_answer","count":5,"points_per_question":2}],"time_limit_minutes":null})}
      end)

      assert {:ok, %{sections: [section]}} = FormatParser.parse("5 short answer")
      assert section["chapter_ids"] == []
    end
  end
end

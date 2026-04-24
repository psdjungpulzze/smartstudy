defmodule FunSheep.Questions.FreeformGraderTest do
  use ExUnit.Case, async: true
  import Mox

  alias FunSheep.AI.ClientMock
  alias FunSheep.Questions.FreeformGrader

  setup :verify_on_exit!

  @question %{
    content: "What is the powerhouse of the cell?",
    answer: "mitochondria"
  }

  describe "grade/2 — correct AI response" do
    test "returns correct: true with no feedback" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": true, "feedback": null})}
      end)

      assert {:ok, %{correct: true, feedback: nil}} =
               FreeformGrader.grade(@question, "the mitochondria")
    end

    test "returns correct: false with feedback" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"correct": false, "feedback": "The answer is mitochondria, not nucleus."})}
      end)

      assert {:ok, %{correct: false, feedback: "The answer is mitochondria, not nucleus."}} =
               FreeformGrader.grade(@question, "the nucleus")
    end

    test "strips markdown fences from response" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, "```json\n{\"correct\": true, \"feedback\": null}\n```"}
      end)

      assert {:ok, %{correct: true, feedback: nil}} =
               FreeformGrader.grade(@question, "mitochondria")
    end
  end

  describe "grade/2 — fallback to exact match on failure" do
    test "falls back when LLM call fails" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:error, :rate_limited}
      end)

      # "mitochondria" exactly matches the reference answer
      assert {:ok, %{correct: true, feedback: nil}} =
               FreeformGrader.grade(@question, "mitochondria")
    end

    test "falls back when LLM returns malformed JSON" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, "I cannot grade this."}
      end)

      assert {:ok, %{correct: false, feedback: nil}} =
               FreeformGrader.grade(@question, "nucleus")
    end

    test "falls back when JSON has unexpected shape" do
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"result": "yes"})}
      end)

      assert {:ok, %{feedback: nil}} = FreeformGrader.grade(@question, "anything")
    end
  end
end

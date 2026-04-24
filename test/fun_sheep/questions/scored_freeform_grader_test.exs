defmodule FunSheep.Questions.ScoredFreeformGraderTest do
  use ExUnit.Case, async: true
  import Mox

  alias FunSheep.AI.ClientMock
  alias FunSheep.Questions.ScoredFreeformGrader

  setup :verify_on_exit!

  @question %{
    content: "What is the powerhouse of the cell?",
    answer: "mitochondria"
  }

  @valid_ai_response ~S({
    "score": 9,
    "max_score": 10,
    "criteria": [
      {"name": "Factual Accuracy", "earned": 4, "max": 4, "comment": "Correct."},
      {"name": "Completeness", "earned": 3, "max": 3, "comment": "Fully addressed."},
      {"name": "Clarity & Logic", "earned": 1, "max": 2, "comment": "Could be more detailed."},
      {"name": "Terminology", "earned": 1, "max": 1, "comment": "Correct term used."}
    ],
    "feedback": "Good answer! The mitochondria is the correct answer.",
    "improvement_hint": "Consider elaborating on how ATP is produced.",
    "is_correct": true
  })

  describe "grade/2 — valid scored response" do
    test "parses a valid scored JSON response correctly" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "scored_freeform_grader"} ->
        {:ok, @valid_ai_response}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "The mitochondria")

      assert result.score == 9
      assert result.max_score == 10
      assert result.is_correct == true
      assert result.grader_path == :scored_ai
      assert is_binary(result.feedback)
      assert is_binary(result.improvement_hint)
      assert length(result.criteria) == 4
    end

    test "is_correct is always score >= 7 even if AI's is_correct differs" do
      # AI says is_correct: false but score is 8 — server must compute is_correct
      ai_response =
        ~S({"score": 8, "max_score": 10, "criteria": [], "feedback": "Good.", "improvement_hint": null, "is_correct": false})

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ai_response}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "mitochondria")

      assert result.score == 8
      # Overrides AI's false — 8 >= 7 means is_correct: true
      assert result.is_correct == true
      assert result.grader_path == :scored_ai
    end

    test "clamps score > 10 to 10" do
      ai_response =
        ~S({"score": 11, "max_score": 10, "criteria": [], "feedback": "Perfect.", "improvement_hint": null, "is_correct": true})

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ai_response}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "mitochondria")
      assert result.score == 10
    end

    test "clamps score < 0 to 0" do
      ai_response =
        ~S({"score": -1, "max_score": 10, "criteria": [], "feedback": "Wrong.", "improvement_hint": "Study more.", "is_correct": false})

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ai_response}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "nucleus")
      assert result.score == 0
      assert result.is_correct == false
    end

    test "rounds non-integer score" do
      ai_response =
        ~S({"score": 7.6, "max_score": 10, "criteria": [], "feedback": "Mostly right.", "improvement_hint": null, "is_correct": true})

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ai_response}
      end)

      assert {:ok, result} =
               ScoredFreeformGrader.grade(@question, "mitochondria are the powerhouse")

      assert result.score == 8
    end

    test "strips markdown fences from response" do
      fenced = "```json\n#{@valid_ai_response}\n```"

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, fenced}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "The mitochondria")
      assert result.score == 9
      assert result.grader_path == :scored_ai
    end
  end

  describe "grade/2 — short-circuit on empty answer" do
    test "returns score 0 immediately without calling AI" do
      # No expect — if AI is called, the test will fail with unexpected call
      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "")

      assert result.score == 0
      assert result.max_score == 10
      assert result.is_correct == false
      assert result.feedback == "No answer provided."
      assert result.improvement_hint == nil
      assert result.criteria == []
      assert result.grader_path == :scored_ai
    end
  end

  describe "grade/2 — fallback to binary grader on AI HTTP error" do
    test "falls back to binary grader on HTTP error, synthesizes score" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "scored_freeform_grader"} ->
        {:error, :rate_limited}
      end)

      # FreeformGrader (binary) also calls the AI client
      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": true, "feedback": null})}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "mitochondria")

      assert result.score == 10
      assert result.is_correct == true
      assert result.grader_path == :binary_ai
    end

    test "falls back to binary grader on malformed JSON" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "scored_freeform_grader"} ->
        {:ok, "This is not JSON at all."}
      end)

      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": false, "feedback": "Wrong"})}
      end)

      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "nucleus")

      assert result.score == 0
      assert result.is_correct == false
      assert result.grader_path == :binary_ai
    end

    test "falls back to exact match when binary grader AI also fails" do
      # Both AI calls fail. FreeformGrader handles its own exact-match fallback
      # internally and still returns {:ok, %{correct: _}} — so grader_path is
      # :binary_ai (the binary grader ran, just via exact match internally).
      expect(ClientMock, :call, fn _sys, _usr, %{source: "scored_freeform_grader"} ->
        {:error, :timeout}
      end)

      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:error, :service_unavailable}
      end)

      # exact match: "mitochondria" == "mitochondria"
      assert {:ok, result} = ScoredFreeformGrader.grade(@question, "mitochondria")

      assert result.score == 10
      assert result.is_correct == true
      # FreeformGrader always returns {:ok, _} (exact match fallback), so path is :binary_ai
      assert result.grader_path == :binary_ai
    end
  end

  describe "grade/2 — missing reference answer" do
    test "falls back to binary grader when question has no reference answer" do
      no_answer_question = %{content: "Explain the water cycle.", answer: ""}

      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": true, "feedback": "Good explanation."})}
      end)

      assert {:ok, result} =
               ScoredFreeformGrader.grade(no_answer_question, "Water evaporates and condenses.")

      assert result.grader_path == :binary_ai
    end
  end
end

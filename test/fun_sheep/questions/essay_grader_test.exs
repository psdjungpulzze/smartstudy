defmodule FunSheep.Questions.EssayGraderTest do
  use ExUnit.Case, async: true
  import Mox

  alias FunSheep.AI.ClientMock
  alias FunSheep.Questions.EssayGrader

  setup :verify_on_exit!

  @rubric %FunSheep.Essays.EssayRubricTemplate{
    id: Ecto.UUID.generate(),
    name: "Test Rubric",
    exam_type: "test",
    max_score: 6,
    mastery_threshold_ratio: 0.67,
    criteria: [
      %{"name" => "Thesis", "max_points" => 2, "description" => "Clear thesis"},
      %{"name" => "Evidence", "max_points" => 4, "description" => "Good evidence"}
    ]
  }

  @question_with_rubric %{
    id: Ecto.UUID.generate(),
    content: "Discuss the causes of the Civil War.",
    answer: "See rubric",
    question_type: :essay,
    essay_rubric_template: @rubric,
    essay_rubric_template_id: nil
  }

  @question_no_rubric %{
    id: Ecto.UUID.generate(),
    content: "Explain photosynthesis.",
    answer: "Photosynthesis is the process by which plants convert light to energy.",
    question_type: :essay,
    essay_rubric_template: nil,
    essay_rubric_template_id: nil
  }

  @valid_essay "The Civil War had multiple causes including slavery, states' rights, and economic differences. The issue of slavery was central to the conflict. Southern states depended on enslaved labor for agriculture. Northern states were industrializing rapidly. These tensions led to secession and war."

  @valid_opus_response Jason.encode!(%{
                         "total_score" => 5,
                         "max_score" => 6,
                         "criteria" => [
                           %{
                             "name" => "Thesis",
                             "earned" => 2,
                             "max" => 2,
                             "comment" => "Clear defensible claim."
                           },
                           %{
                             "name" => "Evidence",
                             "earned" => 3,
                             "max" => 4,
                             "comment" => "Good evidence but needs more analysis."
                           }
                         ],
                         "feedback" =>
                           "Strong thesis. Evidence is present but commentary could be deeper.",
                         "strengths" => ["Clear thesis statement", "Multiple causes identified"],
                         "improvements" => [
                           "Deeper analysis needed",
                           "Add more specific examples"
                         ],
                         "is_correct" => false
                       })

  # ---------------------------------------------------------------------------
  # Blank essay — no AI call
  # ---------------------------------------------------------------------------

  describe "grade/2 — blank essay" do
    test "returns score 0 without making an AI call for empty string" do
      # No Mox expectations — AI should NOT be called
      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, "")
      assert result.total_score == 0
      assert result.is_correct == false
      assert result.feedback == "No essay submitted."
    end

    test "returns score 0 without making an AI call for whitespace-only text" do
      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, "   \n\t  ")
      assert result.total_score == 0
      assert result.is_correct == false
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — Opus with rubric
  # ---------------------------------------------------------------------------

  describe "grade/2 — Opus with rubric" do
    test "parses a valid JSON response correctly" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "essay_grader"} ->
        {:ok, @valid_opus_response}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)

      assert result.total_score == 5
      assert result.max_score == 6
      assert result.grader == :essay_opus
      assert length(result.criteria) == 2
      assert result.feedback != ""
      assert length(result.strengths) == 2
      assert length(result.improvements) == 2
    end

    test "is_correct is computed server-side, NOT from AI-returned flag" do
      # AI says is_correct: false, but 5/6 = 0.83 >= 0.67 threshold → should be true
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, @valid_opus_response}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      # 5/6 = 0.833 >= 0.67
      assert result.is_correct == true
    end

    test "is_correct: false when score is below threshold" do
      low_score_response =
        Jason.encode!(%{
          "total_score" => 2,
          "max_score" => 6,
          "criteria" => [],
          "feedback" => "Needs significant improvement.",
          "strengths" => [],
          "improvements" => ["Develop a thesis"],
          "is_correct" => true
        })

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, low_score_response}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      # 2/6 = 0.333 < 0.67 → false (ignore AI's "true")
      assert result.is_correct == false
    end

    test "strips markdown fences from response" do
      fenced = "```json\n#{@valid_opus_response}\n```"

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, fenced}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      assert result.total_score == 5
    end
  end

  # ---------------------------------------------------------------------------
  # Fallback on Opus failure
  # ---------------------------------------------------------------------------

  describe "grade/2 — fallback on HTTP error" do
    test "falls back to FreeformGrader (binary) when Opus call fails" do
      # Opus fails
      expect(ClientMock, :call, fn _sys, _usr, %{source: "essay_grader"} ->
        {:error, :timeout}
      end)

      # FreeformGrader's Haiku call
      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": true, "feedback": null})}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      # grader is either :scored_sonnet (if ScoredFreeformGrader exists) or :binary_haiku
      assert result.grader in [:scored_sonnet, :binary_haiku]
    end

    test "falls back when AI returns malformed JSON" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "essay_grader"} ->
        {:ok, "I am unable to grade this essay."}
      end)

      # FreeformGrader fallback
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"correct": false, "feedback": "Essay lacks analysis."})}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      assert result.grader in [:scored_sonnet, :binary_haiku]
    end

    test "falls back when JSON response is missing required fields" do
      incomplete_response = Jason.encode!(%{"feedback" => "ok"})

      expect(ClientMock, :call, fn _sys, _usr, %{source: "essay_grader"} ->
        {:ok, incomplete_response}
      end)

      # FreeformGrader fallback
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok, ~S({"correct": false, "feedback": null})}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_with_rubric, @valid_essay)
      assert result.grader in [:scored_sonnet, :binary_haiku]
    end
  end

  # ---------------------------------------------------------------------------
  # Missing rubric fallback
  # ---------------------------------------------------------------------------

  describe "grade/2 — missing rubric" do
    test "falls back to FreeformGrader when question has no rubric" do
      expect(ClientMock, :call, fn _sys, _usr, %{source: "freeform_grader"} ->
        {:ok, ~S({"correct": true, "feedback": "Good essay!"})}
      end)

      assert {:ok, result} = EssayGrader.grade(@question_no_rubric, @valid_essay)
      assert result.grader in [:scored_sonnet, :binary_haiku]
    end

    test "blank essay with no rubric still returns score 0 without AI call" do
      assert {:ok, result} = EssayGrader.grade(@question_no_rubric, "")
      assert result.total_score == 0
      assert result.is_correct == false
    end
  end
end

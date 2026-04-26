defmodule FunSheep.Questions.ValidationBatchTest do
  @moduledoc """
  Tests for Validation.validate_batch/1 — exercises LLM call, JSON parsing,
  missing-verdict fallback, and the full round-trip including apply_verdict.
  """

  use FunSheep.DataCase, async: false

  import Mox

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Questions.Validation
  alias FunSheep.AI.ClientMock

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    Application.put_env(:fun_sheep, :ai_client_impl, ClientMock)

    on_exit(fn ->
      Application.delete_env(:fun_sheep, :ai_client_impl)
    end)

    :ok
  end

  defp create_course do
    {:ok, course} =
      Courses.create_course(%{name: "Validation Test Course", subject: "Mathematics", grade: "11"})

    course
  end

  defp create_question(course, attrs \\ %{}) do
    defaults = %{
      content: "What is the derivative of x^2?",
      answer: "2x",
      question_type: :short_answer,
      difficulty: :medium,
      course_id: course.id,
      validation_status: :pending
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  defp approve_verdict(question_id, score \\ 97.0) do
    %{
      "id" => question_id,
      "verdict" => "approve",
      "topic_relevance_score" => score,
      "topic_relevance_reason" => "on topic",
      "completeness" => %{"passed" => true, "issues" => []},
      "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 50},
      "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
      "explanation" => %{"valid" => true, "suggested_explanation" => nil}
    }
  end

  describe "validate_batch/1 — empty list" do
    test "returns {:ok, %{}} without calling the LLM" do
      assert {:ok, %{}} = Validation.validate_batch([])
    end
  end

  describe "validate_batch/1 — LLM success" do
    test "returns a map keyed by question id when LLM returns valid JSON" do
      course = create_course()
      q = create_question(course)

      response_json = Jason.encode!([approve_verdict(q.id)])

      expect(ClientMock, :call, fn _sys, _user, %{source: "questions_validation_context"} ->
        {:ok, response_json}
      end)

      assert {:ok, verdicts} = Validation.validate_batch([q])
      assert is_map(verdicts)
      assert Map.has_key?(verdicts, q.id)
      assert verdicts[q.id]["verdict"] == "approve"
    end

    test "batches multiple questions in a single LLM call" do
      course = create_course()
      q1 = create_question(course, %{content: "First question?"})
      q2 = create_question(course, %{content: "Second question?"})

      response_json = Jason.encode!([approve_verdict(q1.id), approve_verdict(q2.id)])

      expect(ClientMock, :call, 1, fn _sys, _user, _opts -> {:ok, response_json} end)

      assert {:ok, verdicts} = Validation.validate_batch([q1, q2])
      assert Map.has_key?(verdicts, q1.id)
      assert Map.has_key?(verdicts, q2.id)
    end

    test "fills missing_verdict for questions the LLM skipped" do
      course = create_course()
      q1 = create_question(course, %{content: "Q1?"})
      q2 = create_question(course, %{content: "Q2?"})

      # LLM only returns verdict for q1
      response_json = Jason.encode!([approve_verdict(q1.id)])

      expect(ClientMock, :call, fn _sys, _user, _opts -> {:ok, response_json} end)

      assert {:ok, verdicts} = Validation.validate_batch([q1, q2])

      # q1 has real verdict
      assert verdicts[q1.id]["verdict"] == "approve"

      # q2 gets missing_verdict with pending-retry marker
      assert verdicts[q2.id]["verdict"] == "needs_fix"
      assert verdicts[q2.id]["topic_relevance_reason"] ==
               "Assistant did not return a verdict for this question"
    end

    test "strips markdown fences from JSON response" do
      course = create_course()
      q = create_question(course)

      fenced_response = """
      ```json
      [#{Jason.encode!(approve_verdict(q.id))}]
      ```
      """

      expect(ClientMock, :call, fn _sys, _user, _opts -> {:ok, fenced_response} end)

      assert {:ok, verdicts} = Validation.validate_batch([q])
      assert verdicts[q.id]["verdict"] == "approve"
    end
  end

  describe "validate_batch/1 — LLM error" do
    test "propagates LLM error as {:error, reason}" do
      course = create_course()
      q = create_question(course)

      expect(ClientMock, :call, fn _sys, _user, _opts -> {:error, :timeout} end)

      assert {:error, :timeout} = Validation.validate_batch([q])
    end

    test "returns {:error, :parse_failed} when LLM returns unparseable JSON" do
      course = create_course()
      q = create_question(course)

      expect(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "not json at all"} end)

      assert {:error, :parse_failed} = Validation.validate_batch([q])
    end

    test "returns {:error, :parse_failed} when LLM returns JSON object instead of array" do
      course = create_course()
      q = create_question(course)

      expect(ClientMock, :call, fn _sys, _user, _opts ->
        {:ok, Jason.encode!(%{"verdict" => "approve"})}
      end)

      assert {:error, :parse_failed} = Validation.validate_batch([q])
    end
  end

  describe "validate_batch/1 — missing_verdict detection" do
    test "apply_verdict on missing_verdict keeps status :pending for retry" do
      course = create_course()
      q = create_question(course, %{validation_status: :pending})

      missing = %{
        "topic_relevance_score" => 0,
        "topic_relevance_reason" => "Assistant did not return a verdict for this question",
        "completeness" => %{"passed" => false, "issues" => ["no verdict returned"]},
        "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 0},
        "answer_correct" => %{"correct" => false, "corrected_answer" => nil},
        "explanation" => %{"valid" => false, "suggested_explanation" => nil},
        "verdict" => "needs_fix"
      }

      assert {:ok, updated} = Validation.apply_verdict(q, missing)
      # Missing verdict keeps question in :pending so sweeper can re-queue
      assert updated.validation_status == :pending
      # Increments attempt counter
      assert updated.validation_attempts == 1
    end
  end

  describe "validate_batch/1 — full round-trip" do
    test "applying batch verdicts updates question statuses in DB" do
      course = create_course()
      q1 = create_question(course, %{content: "Pass me?"})
      q2 = create_question(course, %{content: "Reject me?"})

      reject_verdict = %{
        "id" => q2.id,
        "verdict" => "reject",
        "topic_relevance_score" => 30,
        "topic_relevance_reason" => "completely off-topic",
        "completeness" => %{"passed" => false, "issues" => ["off-topic"]},
        "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 0},
        "answer_correct" => %{"correct" => false, "corrected_answer" => nil},
        "explanation" => %{"valid" => false, "suggested_explanation" => nil}
      }

      response_json = Jason.encode!([approve_verdict(q1.id), reject_verdict])
      expect(ClientMock, :call, fn _sys, _user, _opts -> {:ok, response_json} end)

      {:ok, verdicts} = Validation.validate_batch([q1, q2])

      {:ok, updated_q1} = Validation.apply_verdict(q1, verdicts[q1.id])
      {:ok, updated_q2} = Validation.apply_verdict(q2, verdicts[q2.id])

      assert updated_q1.validation_status == :passed
      assert updated_q2.validation_status == :failed
    end
  end
end

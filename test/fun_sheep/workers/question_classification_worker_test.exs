defmodule FunSheep.Workers.QuestionClassificationWorkerTest do
  @moduledoc """
  Regression tests for the classification worker.

  The worker now calls the LLM directly via FunSheep.AI.ClientMock in tests,
  bypassing Interactor entirely.
  """

  use FunSheep.DataCase, async: true
  import Mox

  alias FunSheep.{Courses, Questions}
  alias FunSheep.AI.ClientMock
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.QuestionClassificationWorker

  setup :verify_on_exit!

  defp fixture do
    {:ok, course} = Courses.create_course(%{name: "Math 101", subject: "Math", grade: "10"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Fractions", position: 1, course_id: course.id})

    {:ok, section} =
      Courses.create_section(%{name: "Adding Fractions", position: 1, chapter_id: chapter.id})

    {:ok, question} =
      Questions.create_question(%{
        content: "What is 1/2 + 1/2?",
        answer: "1",
        question_type: :multiple_choice,
        difficulty: :medium,
        course_id: course.id,
        chapter_id: chapter.id,
        validation_status: :passed,
        classification_status: :uncategorized
      })

    %{course: course, chapter: chapter, section: section, question: question}
  end

  describe "LLM call failure" do
    test "leaves the question uncategorized when the LLM is unavailable" do
      %{question: question} = fixture()

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:error, :rate_limited}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok =
                   QuestionClassificationWorker.perform(%Oban.Job{
                     args: %{"question_ids" => [question.id]}
                   })
        end)

      assert log =~ "LLM call failed"

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :uncategorized
      assert is_nil(reloaded.section_id)
      assert is_nil(reloaded.classified_at)
    end
  end

  describe "chapter has no sections" do
    test "auto-creates default Overview section and marks the question :ai_classified without an LLM call" do
      {:ok, course} = Courses.create_course(%{name: "AP Bio", subject: "Biology", grade: "11"})

      {:ok, chapter} =
        Courses.create_chapter(%{name: "Chapter 1: Cells", position: 1, course_id: course.id})

      {:ok, question} =
        Questions.create_question(%{
          content: "What is the powerhouse of the cell?",
          answer: "Mitochondria",
          question_type: :multiple_choice,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: chapter.id,
          validation_status: :passed,
          classification_status: :uncategorized
        })

      # NO mock expectations — the auto-default branch must not call the LLM at all.
      # Any unexpected call to ClientMock.call/3 would fail the test.

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)

      assert reloaded.classification_status == :ai_classified
      assert reloaded.classification_confidence == 1.0
      refute is_nil(reloaded.section_id)
      refute is_nil(reloaded.classified_at)

      [section] = Courses.list_sections_by_chapter(chapter.id)
      assert section.name == "Overview"
      assert section.id == reloaded.section_id

      classification = reloaded.metadata["classification"]
      assert classification["auto_default"] == true
    end
  end

  describe "happy path" do
    test "classifies the question when LLM returns a valid section_number" do
      %{section: section, question: question} = fixture()

      # New shape: LLM returns section_number (1-indexed), worker resolves to UUID.
      expect(ClientMock, :call, fn _sys, _usr, %{source: "question_classification_worker"} ->
        {:ok,
         Jason.encode!(%{
           "section_number" => 1,
           "confidence" => 0.95,
           "rationale" => "clearly an adding-fractions question"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :ai_classified
      assert reloaded.section_id == section.id
    end

    test "still accepts the legacy section_id shape (forward-compat)" do
      %{section: section, question: question} = fixture()

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_id" => section.id,
           "confidence" => 0.9,
           "rationale" => "fallback path"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      assert Repo.get!(Question, question.id).classification_status == :ai_classified
    end

    test "out-of-range section_number routes to :low_confidence (no crash, no hallucination leak)" do
      %{question: question} = fixture()

      # The fixture chapter has exactly 1 section. Asking for #5 must NOT
      # silently pick a random section — it must mark :low_confidence.
      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_number" => 5,
           "confidence" => 0.9,
           "rationale" => "guessing"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :low_confidence
      assert is_nil(reloaded.section_id)
    end
  end

  describe "confidence threshold" do
    setup do
      original = Application.get_env(:fun_sheep, :classification_confidence_threshold)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:fun_sheep, :classification_confidence_threshold)
        else
          Application.put_env(:fun_sheep, :classification_confidence_threshold, original)
        end
      end)

      :ok
    end

    test "default threshold (0.5) accepts mid-confidence picks instead of rotting them at :low_confidence" do
      # The 2026-04-22 incident: LLM consistently returned 0.5–0.7 for valid
      # AP Bio chapter→section assignments, but the old 0.85 threshold
      # rejected all of them. With the new default (0.5), a 0.6 verdict
      # against a valid in-chapter section must come through as :ai_classified.
      %{section: section, question: question} = fixture()

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_id" => section.id,
           "confidence" => 0.6,
           "rationale" => "matches the section reasonably well"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :ai_classified
      assert reloaded.section_id == section.id
      assert reloaded.classification_confidence == 0.6
    end

    test "below-threshold confidence still routes to :low_confidence (no false promotions)" do
      %{question: question} = fixture()

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_id" => Ecto.UUID.generate(),
           "confidence" => 0.3,
           "rationale" => "guessing"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :low_confidence
      assert is_nil(reloaded.section_id)
    end

    test "env override raises threshold above LLM verdict → routes to :low_confidence" do
      %{section: section, question: question} = fixture()

      Application.put_env(:fun_sheep, :classification_confidence_threshold, 0.9)

      expect(ClientMock, :call, fn _sys, _usr, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_id" => section.id,
           "confidence" => 0.7,
           "rationale" => "matches"
         })}
      end)

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)
      assert reloaded.classification_status == :low_confidence
      assert is_nil(reloaded.section_id)
    end
  end
end

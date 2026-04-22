defmodule FunSheep.Workers.QuestionClassificationWorkerTest do
  @moduledoc """
  Regression tests around the 2026-04-22 prod incident where the classifier
  worker discarded `ensure_assistant/0`'s return value and proceeded to call
  `Agents.chat/3` with an unknown assistant name — producing 530 consecutive
  `:assistant_not_found` errors before the operator bumped the assistant
  name.

  These tests drive the worker through the Mox-backed `AgentsMock` so we can
  pin the exact failure mode without a real Interactor round-trip.
  """

  use FunSheep.DataCase, async: true
  import Mox

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Interactor.AgentsMock
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.QuestionClassificationWorker

  setup :verify_on_exit!

  setup do
    # Route Agents calls through the Mox-backed stub for the duration of this
    # test. The default in test env is the real `FunSheep.Interactor.Agents`
    # module (with mock-mode Client responses), so other tests are unaffected.
    Application.put_env(
      :fun_sheep,
      :interactor_agents_impl,
      FunSheep.Interactor.AgentsMock
    )

    on_exit(fn ->
      Application.delete_env(:fun_sheep, :interactor_agents_impl)
    end)

    # persistent_term is process-independent; a cached id from a prior test
    # would make `ensure_assistant/0` skip provisioning entirely. Wipe it.
    :persistent_term.erase({QuestionClassificationWorker, :assistant_id})

    :ok
  end

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

  describe "assistant provisioning failure" do
    test "skips Agents.chat and leaves the question uncategorized" do
      %{question: question} = fixture()

      # Provisioning fails on the very first call. If the short-circuit is
      # broken, the worker would still reach `chat/3` and the test would fail
      # with a Mox "received unexpected call" error — which is precisely the
      # regression guarantee we want.
      expect(AgentsMock, :resolve_or_create_assistant, fn _attrs ->
        {:error, {:assistant_not_found, "question_skill_tagger"}}
      end)

      # No chat/3 expectation — any call to it would fail the test.

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :ok =
                   QuestionClassificationWorker.perform(%Oban.Job{
                     args: %{"question_ids" => [question.id]}
                   })
        end)

      assert log =~ "Assistant not provisioned"

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

      # NO mock expectations — the auto-default branch must not call AI at
      # all (no chat AND no resolve_or_create_assistant). With Mox `expect`
      # absent, any unexpected call fails the test.

      assert :ok =
               QuestionClassificationWorker.perform(%Oban.Job{
                 args: %{"question_ids" => [question.id]}
               })

      reloaded = Repo.get!(Question, question.id)

      assert reloaded.classification_status == :ai_classified
      assert reloaded.classification_confidence == 1.0
      refute is_nil(reloaded.section_id)
      refute is_nil(reloaded.classified_at)

      # The Overview section now exists for that chapter.
      [section] = Courses.list_sections_by_chapter(chapter.id)
      assert section.name == "Overview"
      assert section.id == reloaded.section_id

      # And the metadata is honest about the auto-default path.
      classification = reloaded.metadata["classification"]
      assert classification["auto_default"] == true
    end
  end

  describe "happy path" do
    test "classifies the question when resolve + chat both succeed" do
      %{section: section, question: question} = fixture()

      expect(AgentsMock, :resolve_or_create_assistant, fn _attrs -> {:ok, "mock-id"} end)

      expect(AgentsMock, :chat, fn _name, _prompt, _opts ->
        {:ok,
         Jason.encode!(%{
           "section_id" => section.id,
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
  end
end

defmodule FunSheep.Workers.QuestionValidationWorkerTest do
  @moduledoc """
  Covers the partial-success / total-failure boundary introduced after the
  2026-04-22 stuck-pending incident.

  Before the fix: any sub-batch error raised from the worker, losing progress
  on every prior sub-batch in the same job and eventually discarding it after
  `max_attempts`. Questions in discarded jobs were orphaned at `:pending` —
  the UI's "validating" progress bar froze. See
  `FunSheep.Workers.StuckValidationSweeperWorker` for the recovery path.

  New contract:
    * Sub-batch success → apply verdicts, job stays `:ok`.
    * Mixed success/failure → commit verdicts for the successful sub-batches,
      leave failed ones at `:pending` for the sweeper, return `:ok`.
    * Every sub-batch failed → raise, Oban retries the whole job.
  """

  use FunSheep.DataCase, async: true
  import Mox

  alias FunSheep.{Courses, Questions}
  alias FunSheep.Interactor.AgentsMock
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.QuestionValidationWorker

  setup :verify_on_exit!

  setup do
    Application.put_env(
      :fun_sheep,
      :interactor_agents_impl,
      FunSheep.Interactor.AgentsMock
    )

    on_exit(fn -> Application.delete_env(:fun_sheep, :interactor_agents_impl) end)
    :persistent_term.erase({FunSheep.Questions.Validation, :assistant_id})
    :ok
  end

  # Batch size inside the worker is 10, so 15 questions = 2 sub-batches.
  defp make_questions(n) do
    {:ok, course} =
      Courses.create_course(%{name: "Biology", subject: "Biology", grade: "10"})

    {:ok, chapter} =
      Courses.create_chapter(%{name: "Cells", position: 1, course_id: course.id})

    questions =
      for i <- 1..n do
        {:ok, q} =
          Questions.create_question(%{
            content: "Q#{i}?",
            answer: "A",
            question_type: :short_answer,
            difficulty: :easy,
            course_id: course.id,
            chapter_id: chapter.id,
            validation_status: :pending
          })

        q
      end

    {course, questions}
  end

  defp approve_verdict_json(questions) do
    questions
    |> Enum.map(fn q ->
      %{
        "id" => q.id,
        "topic_relevance_score" => 100,
        "topic_relevance_reason" => "on-topic",
        "completeness" => %{"passed" => true, "issues" => []},
        "categorization" => %{"suggested_chapter_id" => nil, "confidence" => 0},
        "answer_correct" => %{"correct" => true, "corrected_answer" => nil},
        "explanation" => %{"valid" => true, "suggested_explanation" => nil},
        "verdict" => "approve"
      }
    end)
    |> Jason.encode!()
  end

  describe "partial failure" do
    test "commits successful sub-batch and leaves failed sub-batch as :pending without raising" do
      {course, questions} = make_questions(15)
      [first_batch, second_batch] = Enum.chunk_every(questions, 10)

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)

      # Two Interactor calls (one per sub-batch). First succeeds, second errors.
      AgentsMock
      |> expect(:chat, fn _name, _prompt, _opts ->
        {:ok, approve_verdict_json(first_batch)}
      end)
      |> expect(:chat, fn _name, _prompt, _opts ->
        {:error, :timeout}
      end)

      # Should NOT raise — partial progress is valid.
      assert :ok =
               QuestionValidationWorker.perform(%Oban.Job{
                 args: %{
                   "question_ids" => Enum.map(questions, & &1.id),
                   "course_id" => course.id
                 }
               })

      # First batch questions → :passed
      for q <- first_batch do
        assert Repo.get!(Question, q.id).validation_status == :passed
      end

      # Second batch questions stay at :pending, ready for the sweeper
      for q <- second_batch do
        assert Repo.get!(Question, q.id).validation_status == :pending
      end
    end
  end

  describe "total failure" do
    test "raises when every sub-batch errors so Oban retries the job" do
      {course, questions} = make_questions(15)

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)
      expect(AgentsMock, :chat, 2, fn _name, _prompt, _opts -> {:error, :timeout} end)

      assert_raise RuntimeError, ~r/all 2 sub-batches errored/, fn ->
        QuestionValidationWorker.perform(%Oban.Job{
          args: %{
            "question_ids" => Enum.map(questions, & &1.id),
            "course_id" => course.id
          }
        })
      end

      # All questions still :pending — nothing was committed.
      for q <- questions do
        assert Repo.get!(Question, q.id).validation_status == :pending
      end
    end
  end

  describe "happy path" do
    test "full success commits verdicts and returns :ok" do
      {course, questions} = make_questions(5)

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)

      expect(AgentsMock, :chat, fn _name, _prompt, _opts ->
        {:ok, approve_verdict_json(questions)}
      end)

      assert :ok =
               QuestionValidationWorker.perform(%Oban.Job{
                 args: %{
                   "question_ids" => Enum.map(questions, & &1.id),
                   "course_id" => course.id
                 }
               })

      for q <- questions do
        assert Repo.get!(Question, q.id).validation_status == :passed
      end
    end
  end
end

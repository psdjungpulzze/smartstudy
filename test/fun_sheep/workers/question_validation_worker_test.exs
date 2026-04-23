defmodule FunSheep.Workers.QuestionValidationWorkerTest do
  @moduledoc """
  Covers the partial-success / total-failure boundary and immediate retry
  introduced after the 2026-04-22 stuck-pending incident.

  Before the fix: any sub-batch error raised from the worker, losing progress
  on every prior sub-batch in the same job and eventually discarding it after
  `max_attempts`. Questions in discarded jobs were orphaned at `:pending` —
  the UI's "validating" progress bar froze. See
  `FunSheep.Workers.StuckValidationSweeperWorker` for the recovery path.

  Subsequent fix on the same day caps the parse_failed retry loop:
  questions whose batches keep returning unparseable LLM output get marked
  `:failed` after `@max_validation_attempts` attempts so the course can
  finalize honestly instead of staying "still processing" forever.

  Later fix: on partial failure the failed sub-batch's retry-eligible questions
  are immediately re-enqueued (60s scheduled delay) instead of waiting for the
  sweeper's 30-minute stuck threshold. In Oban inline test mode, the scheduled
  job executes synchronously during the same `perform/1` call.

  Contract:
    * Sub-batch success → apply verdicts, job stays `:ok`.
    * Mixed success/failure → commit verdicts for the successful sub-batches,
      immediately re-enqueue retry-eligible questions from failed sub-batches,
      return `:ok`.
    * Every sub-batch failed → raise, Oban retries the whole job (no immediate
      re-enqueue since the job itself will be retried by Oban).
    * Same questions parse-fail @max_validation_attempts times → mark them
      `:failed` with a `validator_unparseable_response` report.
  """

  # Not async: shared `:interactor_agents_impl` Application env races with
  # other validator-touching tests; `:persistent_term` assistant cache is
  # also process-global.
  use FunSheep.DataCase, async: false
  import Mox
  import Ecto.Query

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

  # Worker batch size is 5, so 10 questions = 2 sub-batches.
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
    test "commits successful sub-batch, immediately retries failed sub-batch, returns :ok" do
      {course, questions} = make_questions(10)
      [first_batch, second_batch] = Enum.chunk_every(questions, 5)

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)

      AgentsMock
      # First batch: success
      |> expect(:chat, fn _name, _prompt, _opts ->
        {:ok, approve_verdict_json(first_batch)}
      end)
      # Second batch: failure (triggers immediate re-enqueue)
      |> expect(:chat, fn _name, _prompt, _opts ->
        {:error, :timeout}
      end)
      # Immediate retry of second batch (Oban inline executes it synchronously)
      |> expect(:chat, fn _name, _prompt, _opts ->
        {:ok, approve_verdict_json(second_batch)}
      end)

      assert :ok =
               QuestionValidationWorker.perform(%Oban.Job{
                 args: %{
                   "question_ids" => Enum.map(questions, & &1.id),
                   "course_id" => course.id
                 }
               })

      # First batch: validated immediately
      for q <- first_batch do
        assert Repo.get!(Question, q.id).validation_status == :passed
      end

      # Second batch: retry succeeded — also :passed
      for q <- second_batch do
        assert Repo.get!(Question, q.id).validation_status == :passed
      end
    end

  end

  describe "total failure" do
    test "raises when every sub-batch errors so Oban retries the job" do
      {course, questions} = make_questions(10)

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

      # All questions still :pending — nothing was committed, but attempts
      # were bumped (single attempt — under cap).
      for q <- questions do
        reloaded = Repo.get!(Question, q.id)
        assert reloaded.validation_status == :pending
        assert reloaded.validation_attempts == 1
      end
    end
  end

  describe "parse_failed cap" do
    test "questions hitting @max_validation_attempts get marked :failed honestly" do
      {course, [q1, q2, q3, q4, q5]} = make_questions(5)

      # Pre-bump 3 of them so the next parse_failed pushes them to the cap.
      Repo.update_all(
        from(q in Question,
          where: q.id in ^[q1.id, q2.id, q3.id]
        ),
        set: [validation_attempts: 2]
      )

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)

      expect(AgentsMock, :chat, fn _name, _prompt, _opts ->
        {:ok, "["}
      end)

      assert_raise RuntimeError, fn ->
        QuestionValidationWorker.perform(%Oban.Job{
          args: %{
            "question_ids" => Enum.map([q1, q2, q3, q4, q5], & &1.id),
            "course_id" => course.id
          }
        })
      end

      for id <- [q1.id, q2.id, q3.id] do
        q = Repo.get!(Question, id)
        assert q.validation_status == :failed
        assert q.validation_score == 0.0
        assert q.validation_report["error"] == "validator_unparseable_response"
        assert q.validation_report["attempts"] == 3
      end

      for id <- [q4.id, q5.id] do
        q = Repo.get!(Question, id)
        assert q.validation_status == :pending
        assert q.validation_attempts == 1
      end
    end

    test "course finalizes after every question is settled, even if all :failed" do
      {course, questions} = make_questions(5)

      Repo.update_all(
        from(q in Question, where: q.id in ^Enum.map(questions, & &1.id)),
        set: [validation_attempts: 2]
      )

      expect(AgentsMock, :resolve_or_create_assistant, fn _ -> {:ok, "mock-id"} end)

      expect(AgentsMock, :chat, fn _name, _prompt, _opts ->
        {:ok, "[ truncated"}
      end)

      assert_raise RuntimeError, fn ->
        QuestionValidationWorker.perform(%Oban.Job{
          args: %{
            "question_ids" => Enum.map(questions, & &1.id),
            "course_id" => course.id
          }
        })
      end

      reloaded_course = Courses.get_course!(course.id)
      assert reloaded_course.processing_status == "failed"

      assert reloaded_course.processing_step =~
               "validator returned responses we couldn't read"
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

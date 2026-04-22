defmodule FunSheep.Workers.StuckValidationSweeperWorkerTest do
  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Ecto.Query

  alias FunSheep.Courses
  alias FunSheep.Questions.Question
  alias FunSheep.Repo
  alias FunSheep.Workers.{QuestionValidationWorker, StuckValidationSweeperWorker}

  defp create_course do
    {:ok, course} =
      Courses.create_course(%{name: "Biology", subject: "Biology", grade: "10"})

    course
  end

  defp create_pending_question(course, attrs \\ %{}) do
    {:ok, q} =
      FunSheep.Questions.create_question(
        Map.merge(
          %{
            validation_status: :pending,
            content: "Q?",
            answer: "A",
            question_type: :short_answer,
            difficulty: :easy,
            course_id: course.id
          },
          attrs
        )
      )

    q
  end

  defp backdate_inserted!(%Question{id: id}, minutes_ago) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-minutes_ago * 60, :second)
      |> DateTime.truncate(:second)

    from(q in Question, where: q.id == ^id)
    |> Repo.update_all(set: [inserted_at: at])
  end

  describe "perform/1 default (age threshold)" do
    test "re-enqueues questions older than 30 minutes" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        q = create_pending_question(course)
        backdate_inserted!(q, 45)

        assert :ok = perform_job(StuckValidationSweeperWorker, %{})

        assert_enqueued(
          worker: QuestionValidationWorker,
          args: %{"question_ids" => [q.id], "course_id" => course.id}
        )
      end)
    end

    test "skips questions younger than the threshold" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        _recent = create_pending_question(course)

        assert :ok = perform_job(StuckValidationSweeperWorker, %{})

        refute_enqueued(worker: QuestionValidationWorker)
      end)
    end

    test "skips questions that have already moved past :pending" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        q = create_pending_question(course, %{validation_status: :passed})
        backdate_inserted!(q, 45)

        assert :ok = perform_job(StuckValidationSweeperWorker, %{})

        refute_enqueued(worker: QuestionValidationWorker)
      end)
    end
  end

  describe "perform/1 with force=true" do
    test "sweeps :pending questions regardless of age" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()
        q = create_pending_question(course)

        assert :ok = perform_job(StuckValidationSweeperWorker, %{"force" => true})

        assert_enqueued(
          worker: QuestionValidationWorker,
          args: %{"question_ids" => [q.id], "course_id" => course.id}
        )
      end)
    end

    test "processes multiple stuck courses" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        a = create_course()
        b = create_course()
        q_a = create_pending_question(a)
        q_b = create_pending_question(b)

        assert :ok = perform_job(StuckValidationSweeperWorker, %{"force" => true})

        assert_enqueued(
          worker: QuestionValidationWorker,
          args: %{"question_ids" => [q_a.id], "course_id" => a.id}
        )

        assert_enqueued(
          worker: QuestionValidationWorker,
          args: %{"question_ids" => [q_b.id], "course_id" => b.id}
        )
      end)
    end

    test "chunks a course with many pending questions into multiple validator jobs" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        course = create_course()

        # requeue_pending_validations/1 chunks every 10 — 15 questions = 2 jobs.
        ids =
          for _ <- 1..15 do
            create_pending_question(course).id
          end

        assert :ok = perform_job(StuckValidationSweeperWorker, %{"force" => true})

        enqueued = all_enqueued(worker: QuestionValidationWorker)

        assert length(enqueued) == 2
        total_ids = enqueued |> Enum.flat_map(& &1.args["question_ids"]) |> Enum.sort()
        assert total_ids == Enum.sort(ids)
      end)
    end
  end
end

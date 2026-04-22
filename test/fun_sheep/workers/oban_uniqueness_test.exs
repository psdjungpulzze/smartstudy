defmodule FunSheep.Workers.ObanUniquenessTest do
  @moduledoc """
  Regression tests for the thundering-herd incident on 2026-04-22: a single
  course had 11+ concurrent `AIQuestionGenerationWorker` jobs in the :ai queue,
  starving the Postgrex pool and blocking all validator/classifier work.

  These tests lock in the Oban `unique:` constraints added to the three AI
  workers so duplicate enqueues collapse instead of stacking.
  """
  use FunSheep.DataCase, async: true

  alias FunSheep.Workers.{
    AIQuestionGenerationWorker,
    QuestionClassificationWorker,
    QuestionValidationWorker
  }

  defp with_manual_oban(fun) do
    Oban.Testing.with_testing_mode(:manual, fun)
  end

  defp count_jobs(worker) do
    import Ecto.Query
    worker_string = worker |> to_string() |> String.trim_leading("Elixir.")

    FunSheep.Repo.aggregate(
      from(j in Oban.Job, where: j.worker == ^worker_string),
      :count
    )
  end

  describe "AIQuestionGenerationWorker uniqueness" do
    test "duplicate enqueue with identical args is deduped" do
      with_manual_oban(fn ->
        course_id = Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 AIQuestionGenerationWorker.enqueue(course_id, mode: "from_material", count: 10)

        assert {:ok, %Oban.Job{conflict?: true}} =
                 AIQuestionGenerationWorker.enqueue(course_id, mode: "from_material", count: 10)

        assert count_jobs(AIQuestionGenerationWorker) == 1
      end)
    end

    test "different courses produce independent jobs" do
      with_manual_oban(fn ->
        c1 = Ecto.UUID.generate()
        c2 = Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} = AIQuestionGenerationWorker.enqueue(c1)
        assert {:ok, %Oban.Job{conflict?: false}} = AIQuestionGenerationWorker.enqueue(c2)

        assert count_jobs(AIQuestionGenerationWorker) == 2
      end)
    end

    test "different modes for the same course produce independent jobs" do
      with_manual_oban(fn ->
        course_id = Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 AIQuestionGenerationWorker.enqueue(course_id, mode: "from_material")

        assert {:ok, %Oban.Job{conflict?: false}} =
                 AIQuestionGenerationWorker.enqueue(course_id, mode: "variations")

        assert count_jobs(AIQuestionGenerationWorker) == 2
      end)
    end
  end

  describe "QuestionValidationWorker uniqueness" do
    test "same id batch enqueued twice collapses to one job" do
      with_manual_oban(fn ->
        ids = for _ <- 1..3, do: Ecto.UUID.generate()
        course_id = Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionValidationWorker.enqueue(ids, course_id: course_id)

        assert {:ok, %Oban.Job{conflict?: true}} =
                 QuestionValidationWorker.enqueue(ids, course_id: course_id)

        assert count_jobs(QuestionValidationWorker) == 1
      end)
    end

    test "different course_ids keep jobs independent even with same ids" do
      with_manual_oban(fn ->
        ids = for _ <- 1..3, do: Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionValidationWorker.enqueue(ids, course_id: Ecto.UUID.generate())

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionValidationWorker.enqueue(ids, course_id: Ecto.UUID.generate())

        assert count_jobs(QuestionValidationWorker) == 2
      end)
    end

    test "same id batch in different order still collapses (ids are sorted on enqueue)" do
      with_manual_oban(fn ->
        course_id = Ecto.UUID.generate()
        ids = for _ <- 1..3, do: Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionValidationWorker.enqueue(ids, course_id: course_id)

        assert {:ok, %Oban.Job{conflict?: true}} =
                 QuestionValidationWorker.enqueue(Enum.reverse(ids), course_id: course_id)

        assert count_jobs(QuestionValidationWorker) == 1
      end)
    end
  end

  describe "QuestionClassificationWorker uniqueness" do
    test "same id batch enqueued twice collapses to one job" do
      with_manual_oban(fn ->
        ids = for _ <- 1..3, do: Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionClassificationWorker.enqueue_for_questions(ids)

        assert {:ok, %Oban.Job{conflict?: true}} =
                 QuestionClassificationWorker.enqueue_for_questions(ids)

        assert count_jobs(QuestionClassificationWorker) == 1
      end)
    end

    test "same chapter enqueued twice collapses" do
      with_manual_oban(fn ->
        chapter_id = Ecto.UUID.generate()

        assert {:ok, %Oban.Job{conflict?: false}} =
                 QuestionClassificationWorker.enqueue_for_chapter(chapter_id)

        assert {:ok, %Oban.Job{conflict?: true}} =
                 QuestionClassificationWorker.enqueue_for_chapter(chapter_id)

        assert count_jobs(QuestionClassificationWorker) == 1
      end)
    end
  end
end

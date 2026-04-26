defmodule FunSheep.Workers.CrawlBatchProgressWorkerTest do
  use FunSheep.DataCase, async: false

  import Ecto.Query

  alias FunSheep.{Content, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Scraper.CrawlBatch
  alias FunSheep.Workers.CrawlBatchProgressWorker

  setup do
    course = ContentFixtures.create_course()
    %{course: course}
  end

  defp insert_batch(course, attrs \\ %{}) do
    base = %{
      course_id: course.id,
      strategy: "web_search",
      test_type: course.catalog_test_type || "sat",
      total_urls: 0,
      processed_urls: 0,
      questions_extracted: 0,
      status: "running"
    }

    %CrawlBatch{}
    |> CrawlBatch.changeset(Map.merge(base, attrs))
    |> Repo.insert!()
  end

  defp create_source(course, status) do
    {:ok, ds} =
      Content.create_discovered_source(%{
        course_id: course.id,
        url: "https://example.com/#{:erlang.unique_integer([:positive])}",
        title: "Test Source",
        source_type: "practice_test",
        status: status
      })

    ds
  end

  defp create_web_question(course) do
    {:ok, q} =
      FunSheep.Questions.create_question(%{
        course_id: course.id,
        content: "What is 2 + 2?",
        answer: "4",
        question_type: :short_answer,
        difficulty: :easy,
        source_type: :web_scraped
      })

    q
  end

  describe "perform/1" do
    test "updates processed_urls and questions_extracted for running batch", %{course: course} do
      batch = insert_batch(course, %{status: "running", total_urls: 3})

      create_source(course, "processed")
      create_source(course, "processed")
      create_source(course, "discovered")
      create_web_question(course)

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      updated = Repo.get!(CrawlBatch, batch.id)
      assert updated.processed_urls == 2
      assert updated.questions_extracted == 1
      assert updated.status == "running"
    end

    test "marks batch 'complete' when all sources are processed", %{course: course} do
      batch = insert_batch(course, %{status: "running", total_urls: 2})

      create_source(course, "processed")
      create_source(course, "processed")

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      updated = Repo.get!(CrawlBatch, batch.id)
      assert updated.status == "complete"
      assert updated.processed_urls == 2
    end

    test "marks batch 'complete' when failed/skipped count toward processed", %{course: course} do
      batch = insert_batch(course, %{status: "enqueued", total_urls: 3})

      create_source(course, "processed")
      create_source(course, "failed")
      create_source(course, "skipped")

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      updated = Repo.get!(CrawlBatch, batch.id)
      assert updated.status == "complete"
    end

    test "preserves 'enqueued' status when still processing", %{course: course} do
      batch = insert_batch(course, %{status: "enqueued", total_urls: 3})

      create_source(course, "processed")
      create_source(course, "scraping")
      create_source(course, "discovered")

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      updated = Repo.get!(CrawlBatch, batch.id)
      assert updated.status == "enqueued"
    end

    test "skips batches with 'complete' or 'failed' status", %{course: course} do
      completed_batch = insert_batch(course, %{status: "complete", total_urls: 1})
      failed_batch = insert_batch(course, %{status: "failed", total_urls: 1})

      create_source(course, "processed")

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      # Completed and failed batches must not be touched
      assert Repo.get!(CrawlBatch, completed_batch.id).processed_urls == 0
      assert Repo.get!(CrawlBatch, failed_batch.id).processed_urls == 0
    end

    test "handles multiple courses independently", %{course: course1} do
      course2 = ContentFixtures.create_course()

      batch1 = insert_batch(course1, %{status: "running", total_urls: 2})
      batch2 = insert_batch(course2, %{status: "running", total_urls: 1})

      create_source(course1, "processed")
      create_source(course1, "processed")
      create_source(course2, "processed")

      assert :ok = CrawlBatchProgressWorker.perform(%Oban.Job{args: %{}, id: 1})

      assert Repo.get!(CrawlBatch, batch1.id).status == "complete"
      assert Repo.get!(CrawlBatch, batch2.id).status == "complete"
    end
  end
end

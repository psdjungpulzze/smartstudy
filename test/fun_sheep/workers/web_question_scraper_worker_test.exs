defmodule FunSheep.Workers.WebQuestionScraperWorkerTest do
  @moduledoc """
  Integration tests for the WebQuestionScraperWorker coordinator.

  Tests verify the fan-out behaviour: for N pending discovered_sources the
  coordinator must enqueue exactly N WebSourceScraperWorker Oban jobs.

  Oban is run in :manual mode so that enqueued WebSourceScraperWorker jobs
  are inserted into oban_jobs but not executed — avoiding AI mock calls.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Ecto.Query

  alias FunSheep.{Content, Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Workers.{WebQuestionScraperWorker, WebSourceScraperWorker}

  setup do
    course = ContentFixtures.create_course()
    %{course: course}
  end

  defp insert_discovered_source(course, attrs \\ %{}) do
    defaults = %{
      course_id: course.id,
      url: "https://example.com/#{:erlang.unique_integer([:positive])}",
      title: "Test Source",
      source_type: "practice_test",
      status: "discovered"
    }

    {:ok, ds} = Content.create_discovered_source(Map.merge(defaults, attrs))
    ds
  end

  defp run_coordinator(course_id) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      WebQuestionScraperWorker.perform(%Oban.Job{
        args: %{"course_id" => course_id},
        id: 1
      })
    end)
  end

  describe "perform/1 — coordinator fan-out" do
    test "enqueues exactly N WebSourceScraperWorker jobs for N discovered sources", %{
      course: course
    } do
      sources = for _ <- 1..4, do: insert_discovered_source(course)

      assert :ok = run_coordinator(course.id)

      # Assert each source got its own job inserted
      for source <- sources do
        assert_enqueued(
          worker: WebSourceScraperWorker,
          args: %{"source_id" => source.id},
          queue: :web_scrape
        )
      end
    end

    test "does not enqueue jobs for sources that are not in 'discovered' status", %{
      course: course
    } do
      good_source = insert_discovered_source(course, %{status: "discovered"})
      insert_discovered_source(course, %{status: "scraped"})
      insert_discovered_source(course, %{status: "processed"})
      insert_discovered_source(course, %{status: "failed"})

      run_coordinator(course.id)

      # Only the "discovered" source should be enqueued
      assert_enqueued(
        worker: WebSourceScraperWorker,
        args: %{"source_id" => good_source.id}
      )

      all_jobs =
        from(j in Oban.Job, where: j.worker == "FunSheep.Workers.WebSourceScraperWorker")
        |> Repo.all()

      assert length(all_jobs) == 1,
             "Only 'discovered' sources should be enqueued, got #{length(all_jobs)}"
    end

    test "creates a CrawlBatch record with status 'enqueued'", %{course: course} do
      for _ <- 1..3, do: insert_discovered_source(course)

      run_coordinator(course.id)

      batch =
        from(b in FunSheep.Scraper.CrawlBatch, where: b.course_id == ^course.id)
        |> Repo.one()

      assert batch != nil, "CrawlBatch should be created"
      assert batch.status == "enqueued"
      assert batch.total_urls == 3
    end

    test "returns :ok with no sources and no jobs enqueued", %{course: course} do
      assert :ok = run_coordinator(course.id)

      refute_enqueued(worker: WebSourceScraperWorker)
    end

    test "raises for an unknown course_id" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        run_coordinator(fake_id)
      end
    end
  end

  describe "enqueue/1" do
    test "inserts a WebQuestionScraperWorker Oban job", %{course: course} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = WebQuestionScraperWorker.enqueue(course.id)

        assert_enqueued(
          worker: WebQuestionScraperWorker,
          args: %{"course_id" => course.id},
          queue: :ai
        )
      end)
    end

    test "deduplicates jobs for the same course within uniqueness window", %{course: course} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job1} = WebQuestionScraperWorker.enqueue(course.id)
        {:ok, job2} = WebQuestionScraperWorker.enqueue(course.id)

        # Second insert should return the existing job (Oban uniqueness)
        assert job1.id == job2.id
      end)
    end
  end
end

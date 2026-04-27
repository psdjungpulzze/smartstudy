defmodule FunSheep.Workers.WebPipelineIntegrationTest do
  @moduledoc """
  Phase 7.2 — Mox-based end-to-end pipeline integration test.

  Tests the coordinator fan-out + per-source scrape pipeline:
    1. Pre-seed a DiscoveredSource with status "discovered".
    2. Run WebQuestionScraperWorker (coordinator) in manual Oban mode.
    3. Assert WebSourceScraperWorker jobs were enqueued.
    4. Run WebSourceScraperWorker directly with Req.Test stub returning fixture HTML.
    5. Assert questions were inserted with source_type :web_scraped.
    6. Assert 0 duplicate insertions on second run (deduplication check).
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox
  import Ecto.Query

  alias FunSheep.Repo
  alias FunSheep.ContentFixtures
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.{WebQuestionScraperWorker, WebSourceScraperWorker}
  alias FunSheep.AI.ClientMock

  setup :verify_on_exit!
  setup :set_mox_global

  @fixture_html File.read!(
                  Path.expand(
                    "../../fixtures/scraper/varsity_tutors/question_page.html",
                    __DIR__
                  )
                )

  setup do
    Application.put_env(:fun_sheep, :ai_client_impl, ClientMock)
    # Stub AI so any Generic-path fallback is a no-op returning empty list
    stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

    on_exit(fn ->
      Application.delete_env(:fun_sheep, :ai_client_impl)
      Application.delete_env(:fun_sheep, :scraper_req_opts)
    end)

    :ok
  end

  defp create_course do
    ContentFixtures.create_course(%{
      catalog_test_type: "sat",
      catalog_subject: "mathematics",
      access_level: "premium"
    })
  end

  defp insert_source(course, attrs \\ %{}) do
    defaults = %{
      course_id: course.id,
      url: "https://www.varsitytutors.com/sat_math-practice-tests",
      title: "SAT Math Practice",
      source_type: "practice_test",
      status: "discovered",
      discovery_strategy: "registry"
    }

    %DiscoveredSource{}
    |> DiscoveredSource.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp stub_req_with(html_body) do
    Req.Test.stub(WebSourceScraperWorker, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/render"} ->
          # Renderer endpoint — return JSON with content key
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => html_body}))

        _ ->
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(200, html_body)
      end
    end)

    Application.put_env(:fun_sheep, :scraper_req_opts, plug: {Req.Test, WebSourceScraperWorker})
  end

  # -------------------------------------------------------------------------
  # Coordinator fan-out
  # -------------------------------------------------------------------------

  describe "coordinator fan-out" do
    test "enqueues one WebSourceScraperWorker job per discovered source" do
      course = create_course()
      source = insert_source(course)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert :ok =
                 WebQuestionScraperWorker.perform(%Oban.Job{
                   args: %{"course_id" => course.id},
                   id: 1
                 })
      end)

      assert_enqueued(worker: WebSourceScraperWorker, args: %{"source_id" => source.id})
    end

    test "coordinator skips non-discovered sources" do
      course = create_course()
      pending = insert_source(course, %{url: "https://www.varsitytutors.com/pending"})
      done = insert_source(course, %{status: "scraped", url: "https://www.varsitytutors.com/done"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        WebQuestionScraperWorker.perform(%Oban.Job{args: %{"course_id" => course.id}, id: 1})
      end)

      assert_enqueued(worker: WebSourceScraperWorker, args: %{"source_id" => pending.id})
      refute_enqueued(worker: WebSourceScraperWorker, args: %{"source_id" => done.id})
    end
  end

  # -------------------------------------------------------------------------
  # Per-source scraper with Req.Test-stubbed HTTP
  # -------------------------------------------------------------------------

  describe "per-source scraper (Req.Test stub)" do
    # Run the scraper in manual Oban mode so that downstream workers
    # (QuestionValidationWorker) are enqueued but not executed inline.
    defp run_scraper(source_id) do
      Oban.Testing.with_testing_mode(:manual, fn ->
        WebSourceScraperWorker.perform(%Oban.Job{args: %{"source_id" => source_id}, id: 1})
      end)
    end

    test "extracts and inserts web_scraped questions from VarsityTutors fixture HTML" do
      course = create_course()
      source = insert_source(course)
      stub_req_with(@fixture_html)

      assert :ok = run_scraper(source.id)

      questions =
        from(q in Question,
          where: q.course_id == ^course.id and q.source_type == :web_scraped
        )
        |> Repo.all()

      assert length(questions) >= 1,
             "Expected >= 1 web_scraped question, got #{length(questions)}"
    end

    test "inserted questions have source_url matching the scraped source" do
      course = create_course()
      source = insert_source(course)
      stub_req_with(@fixture_html)

      run_scraper(source.id)

      questions =
        from(q in Question,
          where: q.course_id == ^course.id and q.source_type == :web_scraped
        )
        |> Repo.all()

      Enum.each(questions, fn q ->
        assert q.source_url == source.url
      end)
    end

    test "re-running the scraper on the same source does not duplicate questions" do
      course = create_course()
      source = insert_source(course)
      stub_req_with(@fixture_html)

      run_scraper(source.id)

      count_after_first =
        from(q in Question,
          where: q.course_id == ^course.id and q.source_type == :web_scraped
        )
        |> Repo.aggregate(:count)

      assert count_after_first >= 1

      Repo.get!(DiscoveredSource, source.id)
      |> DiscoveredSource.changeset(%{status: "discovered"})
      |> Repo.update!()

      stub_req_with(@fixture_html)
      run_scraper(source.id)

      count_after_second =
        from(q in Question,
          where: q.course_id == ^course.id and q.source_type == :web_scraped
        )
        |> Repo.aggregate(:count)

      assert count_after_first == count_after_second,
             "Re-scraping produced duplicates: #{count_after_first} → #{count_after_second}"
    end
  end
end

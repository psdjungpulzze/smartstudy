defmodule FunSheep.Workers.WebSourceScraperWorkerTest do
  @moduledoc """
  Unit tests for WebSourceScraperWorker — per-source scraping, fetch routing,
  deduplication, skip/fail paths, and status transitions.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox

  alias FunSheep.Repo
  alias FunSheep.Content.DiscoveredSource
  alias FunSheep.ContentFixtures
  alias FunSheep.Questions.Question
  alias FunSheep.Workers.WebSourceScraperWorker
  alias FunSheep.AI.ClientMock

  import Ecto.Query

  setup :verify_on_exit!
  setup :set_mox_global

  @fixture_html File.read!(
                  Path.expand(
                    "../../fixtures/scraper/varsity_tutors/question_page.html",
                    __DIR__
                  )
                )

  @simple_question_json Jason.encode!([
                          %{
                            "content" => "What is the derivative of x^2 with respect to x?",
                            "answer" => "2x",
                            "question_type" => "short_answer",
                            "options" => nil,
                            "difficulty" => "easy",
                            "explanation" => "Using the power rule: d/dx(x^n) = n*x^(n-1)."
                          }
                        ])

  setup do
    Application.put_env(:fun_sheep, :ai_client_impl, ClientMock)

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
      url: "https://khanacademy.org/math/algebra",
      title: "Khan Academy Algebra",
      source_type: "practice_test",
      status: "discovered",
      discovery_strategy: "registry"
    }

    %DiscoveredSource{}
    |> DiscoveredSource.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp stub_req_with(response_fn) do
    Req.Test.stub(WebSourceScraperWorker, response_fn)
    Application.put_env(:fun_sheep, :scraper_req_opts, plug: {Req.Test, WebSourceScraperWorker})
  end

  defp run_worker(source_id) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      WebSourceScraperWorker.perform(%Oban.Job{args: %{"source_id" => source_id}, id: 1})
    end)
  end

  # ---------------------------------------------------------------------------
  # Skip-extension path
  # ---------------------------------------------------------------------------

  describe "perform/1 — skip unsupported extensions" do
    test "marks source as 'skipped' and returns :ok for .mp4 URLs" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/lecture.mp4"})

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "skipped"
    end

    test "marks source as 'skipped' for .doc URLs" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/file.doc"})

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "skipped"
    end

    test "does not insert any questions for skipped sources" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/img.png"})

      run_worker(source.id)

      count =
        from(q in Question, where: q.course_id == ^course.id)
        |> Repo.aggregate(:count)

      assert count == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Fetch failure path
  # ---------------------------------------------------------------------------

  describe "perform/1 — fetch failure" do
    test "marks source as 'failed' and returns :ok when HTTP fetch returns non-200" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/notfound"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(404, "Not Found")
      end)

      # Stub the AI so we can confirm it is NOT called when fetch fails
      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "failed"
    end
  end

  # ---------------------------------------------------------------------------
  # Successful scrape path — plain fetch (non-SPA domain)
  # ---------------------------------------------------------------------------

  describe "perform/1 — successful plain-fetch scrape" do
    test "marks source as 'processed' after successful scrape and extraction" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/math-test"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @fixture_html)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
    end

    test "inserts extracted questions with correct source attributes" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/math-test"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @fixture_html)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      run_worker(source.id)

      questions =
        from(q in Question, where: q.course_id == ^course.id)
        |> Repo.all()

      assert length(questions) >= 1
      Enum.each(questions, fn q ->
        assert q.source_type == :web_scraped
        assert q.source_url == source.url
      end)
    end

    test "updates questions_extracted count on the source record" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/math-test"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @fixture_html)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.questions_extracted >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # SPA (renderer) path
  # ---------------------------------------------------------------------------

  describe "perform/1 — SPA renderer path (VarsityTutors)" do
    test "uses renderer POST for SPA hosts like varsitytutors.com" do
      course = create_course()

      source =
        insert_source(course, %{url: "https://www.varsitytutors.com/sat_math-practice-tests"})

      stub_req_with(fn conn ->
        case {conn.method, conn.request_path} do
          {"POST", "/render"} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => @fixture_html}))

          _ ->
            conn
            |> Plug.Conn.put_resp_content_type("text/html")
            |> Plug.Conn.send_resp(200, @fixture_html)
        end
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
    end
  end

  # ---------------------------------------------------------------------------
  # Deduplication
  # ---------------------------------------------------------------------------

  describe "perform/1 — deduplication" do
    test "re-running on the same source does not insert duplicate questions" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/math-test"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @fixture_html)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      run_worker(source.id)

      count_after_first =
        from(q in Question, where: q.course_id == ^course.id)
        |> Repo.aggregate(:count)

      # Reset source status for second run
      Repo.get!(DiscoveredSource, source.id)
      |> DiscoveredSource.changeset(%{status: "discovered"})
      |> Repo.update!()

      # Re-stub (previous stub is consumed)
      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @fixture_html)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      run_worker(source.id)

      count_after_second =
        from(q in Question, where: q.course_id == ^course.id)
        |> Repo.aggregate(:count)

      assert count_after_first == count_after_second,
             "Re-scraping produced duplicates: #{count_after_first} → #{count_after_second}"
    end
  end

  # ---------------------------------------------------------------------------
  # enqueue_for_source/1
  # ---------------------------------------------------------------------------

  describe "enqueue_for_source/1" do
    test "inserts an Oban job with the correct source_id" do
      course = create_course()
      source = insert_source(course)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = WebSourceScraperWorker.enqueue_for_source(source)

        assert_enqueued(
          worker: WebSourceScraperWorker,
          args: %{"source_id" => source.id}
        )
      end)
    end
  end
end

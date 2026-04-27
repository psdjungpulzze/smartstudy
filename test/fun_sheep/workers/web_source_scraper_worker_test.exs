defmodule FunSheep.Workers.WebSourceScraperWorkerTest do
  @moduledoc """
  Unit tests for WebSourceScraperWorker — per-source scraping, fetch routing,
  deduplication, skip/fail paths, and status transitions.
  """

  use FunSheep.DataCase, async: false
  use Oban.Testing, repo: FunSheep.Repo

  import Mox

  alias FunSheep.{Courses, Repo}
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
  # Legacy extraction fallback (Extractor returns empty → regex + AI chunks)
  # ---------------------------------------------------------------------------

  describe "perform/1 — legacy extraction fallback" do
    test "exercises regex and AI chunk paths when Extractor.extract returns empty" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/worksheet"})

      # HTML large enough to bypass the plain-fetch threshold
      html_body =
        "<html><body><h1>Algebra Worksheet</h1>" <>
          String.duplicate(
            "<p>This is educational content about algebra covering equations and functions in depth.</p>",
            40
          ) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      # First call: Extractor.extract → empty (so legacy path runs)
      # Second call: extract_with_ai chunk → real question (so parse_ai_questions runs)
      stub(ClientMock, :call, fn
        _sys, _user, %{source: "questions_extractor"} ->
          {:ok, "[]"}

        _sys, _user, %{source: "web_source_scraper_worker"} ->
          {:ok,
           Jason.encode!([
             %{
               "content" => "What is the slope of the line y = 3x + 2 in slope-intercept form?",
               "answer" => "3",
               "question_type" => "short_answer",
               "difficulty" => "easy"
             }
           ])}
      end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
      # At least 1 question from the AI chunk path
      assert updated.questions_extracted >= 1
    end

    test "source is processed with 0 questions when all extraction paths return empty" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/prose-only"})

      html_body =
        "<html><body>" <>
          String.duplicate("<p>This page contains only prose with no practice questions.</p>", 30) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
      assert updated.questions_extracted == 0
    end

    test "AI chunk error is handled gracefully — source still processed" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/ai-chunk-error"})

      html_body =
        "<html><body>" <>
          String.duplicate("<p>Educational content covering biology and cell division topics.</p>", 30) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      stub(ClientMock, :call, fn
        _sys, _user, %{source: "questions_extractor"} -> {:ok, "[]"}
        _sys, _user, %{source: "web_source_scraper_worker"} -> {:error, :timeout}
      end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
      assert updated.questions_extracted == 0
    end

    test "AI chunk returns true/false questions — exercises normalize_tf variants" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/tf-worksheet"})

      html_body =
        "<html><body>" <>
          String.duplicate("<p>Biology review worksheet covering cell biology and genetics topics.</p>", 30) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      # Return three true/false questions covering all normalize_tf branches:
      # "True" (capitalized), "true" (lowercase), "False" (default catch-all)
      stub(ClientMock, :call, fn
        _sys, _user, %{source: "questions_extractor"} ->
          {:ok, "[]"}

        _sys, _user, %{source: "web_source_scraper_worker"} ->
          {:ok,
           Jason.encode!([
             %{
               "content" =>
                 "Mitochondria are often called the powerhouse of the cell because they produce ATP energy.",
               "answer" => "True",
               "question_type" => "true_false",
               "difficulty" => "easy"
             },
             %{
               "content" =>
                 "DNA replication occurs during the S phase of the cell cycle in eukaryotic cells.",
               "answer" => "true",
               "question_type" => "true_false",
               "difficulty" => "medium"
             },
             %{
               "content" =>
                 "All prokaryotic cells have a nucleus enclosed by a nuclear membrane for DNA storage.",
               "answer" => "False",
               "question_type" => "true_false",
               "difficulty" => "hard"
             }
           ])}
      end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
      assert updated.questions_extracted >= 1
    end

    test "question content matching a chapter name gets assigned to that chapter" do
      course = create_course()
      # Insert a chapter whose name has keywords that appear in the question
      {:ok, chapter} =
        Courses.create_chapter(%{course_id: course.id, name: "Algebra Fundamentals", position: 1})

      source = insert_source(course, %{url: "https://example.com/algebra-test"})

      html_body =
        "<html><body>" <>
          String.duplicate("<p>Algebra fundamentals practice worksheet covering equations and expressions.</p>", 30) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      stub(ClientMock, :call, fn
        _sys, _user, %{source: "questions_extractor"} ->
          {:ok, "[]"}

        _sys, _user, %{source: "web_source_scraper_worker"} ->
          {:ok,
           Jason.encode!([
             %{
               "content" => "What are the fundamental algebra rules for solving equations?",
               "answer" => "algebra rules for equations",
               "question_type" => "free_response",
               "difficulty" => "medium"
             }
           ])}
      end)

      assert :ok = run_worker(source.id)

      questions =
        from(q in Question,
          where: q.course_id == ^course.id and q.chapter_id == ^chapter.id
        )
        |> Repo.all()

      assert length(questions) >= 1
    end

    test "text exceeding chunk size is split into multiple AI chunks" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/long-practice"})

      # Paragraph repeated enough times to exceed the 24000-char chunk size after stripping
      paragraph =
        "This is detailed educational content about algebra, geometry, trigonometry, and calculus. "

      html_body =
        "<html><body>" <>
          String.duplicate("<p>#{paragraph}</p>", 400) <>
          "</body></html>"

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, html_body)
      end)

      # Both Extractor.extract and each chunk call return []
      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
    end
  end

  # ---------------------------------------------------------------------------
  # Binary document routing (.docx / .pdf)
  # ---------------------------------------------------------------------------

  describe "perform/1 — binary document download failure" do
    test "marks source 'failed' when DOCX fetch returns non-200" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/worksheet.docx"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(404, "Not Found")
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "failed"
    end

    test "marks source 'failed' when PDF fetch returns non-200" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/practice.pdf"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(403, "Forbidden")
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "failed"
    end

    test "marks source 'failed' when PPTX fetch returns non-200" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/slides.pptx"})

      stub_req_with(fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(500, "Server Error")
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "failed"
    end
  end

  # ---------------------------------------------------------------------------
  # Plain-fetch fails → renderer fallback paths
  # ---------------------------------------------------------------------------

  describe "perform/1 — plain-fetch failure with renderer fallback" do
    test "marks source 'failed' when plain fetch errors and renderer also errors" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/unreachable"})

      stub_req_with(fn conn ->
        # 400 is used (not 5xx) to avoid Req's built-in retry logic
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(400, "Bad Request")
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "failed"
    end

    test "uses original plain-fetch result when renderer returns smaller response" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/small-then-renderer-smaller"})

      # Plain fetch returns tiny content; renderer returns even smaller content
      tiny_html = "<html><body>Loading...</body></html>"
      tinier_response = "{}"

      stub_req_with(fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_resp_content_type("text/html")
            |> Plug.Conn.send_resp(200, tiny_html)

          "POST" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => tinier_response}))
        end
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, "[]"} end)

      # Should still succeed (using the plain-fetch tiny response)
      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
    end

    test "marks source 'processed' when plain GET errors but renderer succeeds" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/get-error-renderer-ok"})

      stub_req_with(fn conn ->
        case conn.method do
          "GET" ->
            conn
            |> Plug.Conn.put_resp_content_type("text/plain")
            |> Plug.Conn.send_resp(400, "Bad Request")

          "POST" ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => @fixture_html}))
        end
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
    end
  end

  # ---------------------------------------------------------------------------
  # Plain-fetch fallback to renderer when response is too small
  # ---------------------------------------------------------------------------

  describe "perform/1 — plain fetch falls back to renderer for small response" do
    test "uses renderer when plain response is too small and renderer returns more content" do
      course = create_course()
      source = insert_source(course, %{url: "https://example.com/spa-content"})

      tiny_html = "<html><body>Loading...</body></html>"
      assert byte_size(tiny_html) < 1_500

      stub_req_with(fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", _} ->
            conn
            |> Plug.Conn.put_resp_content_type("text/html")
            |> Plug.Conn.send_resp(200, tiny_html)

          {"POST", "/render"} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => @fixture_html}))
        end
      end)

      stub(ClientMock, :call, fn _sys, _user, _opts -> {:ok, @simple_question_json} end)

      assert :ok = run_worker(source.id)

      updated = Repo.get!(DiscoveredSource, source.id)
      assert updated.status == "processed"
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

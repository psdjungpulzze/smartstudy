defmodule FunSheepWeb.QuestionBankLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Courses, Questions}

  # ── Session helpers ───────────────────────────────────────────────────────

  @student_uuid "00000000-0000-0000-0000-000000000001"
  @admin_uuid "00000000-0000-0000-0000-000000000002"

  defp student_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: @student_uuid,
      dev_user: %{
        "id" => @student_uuid,
        "role" => "student",
        "email" => "student@test.com",
        "display_name" => "Test Student",
        "user_role_id" => @student_uuid
      }
    })
  end

  defp admin_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: @admin_uuid,
      dev_user: %{
        "id" => @admin_uuid,
        "role" => "admin",
        "email" => "admin@test.com",
        "display_name" => "Test Admin",
        "user_role_id" => @admin_uuid
      }
    })
  end

  # ── Fixtures ──────────────────────────────────────────────────────────────

  defp make_course do
    {:ok, course} =
      Courses.create_course(%{name: "AP Biology", subject: "Biology", grade: "11"})

    course
  end

  defp make_chapter(course, name \\ nil) do
    {:ok, ch} =
      Courses.create_chapter(%{
        name: name || "Ch #{System.unique_integer([:positive])}",
        position: System.unique_integer([:positive]),
        course_id: course.id
      })

    ch
  end

  defp make_section(chapter, name \\ nil) do
    {:ok, sec} =
      Courses.create_section(%{
        name: name || "Sec #{System.unique_integer([:positive])}",
        position: System.unique_integer([:positive]),
        chapter_id: chapter.id
      })

    sec
  end

  defp make_question(course, attrs \\ %{}) do
    defaults = %{
      content: "Question #{System.unique_integer([:positive])}?",
      answer: "Answer",
      question_type: :multiple_choice,
      difficulty: :medium,
      course_id: course.id,
      validation_status: :passed
    }

    {:ok, q} = Questions.create_question(Map.merge(defaults, attrs))
    q
  end

  # ── Mount ─────────────────────────────────────────────────────────────────

  describe "mount" do
    test "renders question bank page for student", %{conn: conn} do
      course = make_course()
      conn = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/questions")

      assert html =~ "Question Bank"
      assert html =~ course.name
    end

    test "shows chapter tree when course has chapters", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "Cell Biology")
      _sec = make_section(ch, "Cell Structure")
      make_question(course, %{chapter_id: ch.id})

      conn = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/questions")

      assert html =~ "Cell Biology"
    end

    test "shows Add Question button for admin but not student", %{conn: conn} do
      course = make_course()

      {:ok, _view, admin_html} =
        live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      {:ok, _view, student_html} =
        live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      assert admin_html =~ "Add Question"
      refute student_html =~ "Add Question"
    end

    test "shows coverage bar for admin", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "Coverage"
    end

    test "does not show coverage bar for student", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      refute html =~ "coverage_pct" || html =~ "sections have questions"
    end
  end

  # ── Chapter/Section selection ─────────────────────────────────────────────

  describe "select_chapter event" do
    test "loads questions for the selected chapter", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "Genetics")
      make_question(course, %{chapter_id: ch.id, content: "What is DNA?"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      html = render_click(view, "select_chapter", %{"id" => ch.id})
      assert html =~ "What is DNA?"
    end

    test "expands the chapter in the sidebar", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "Evolution")
      _sec = make_section(ch, "Natural Selection")
      make_question(course, %{chapter_id: ch.id})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      html = render_click(view, "select_chapter", %{"id" => ch.id})
      assert html =~ "Natural Selection"
    end
  end

  describe "select_section event" do
    test "loads questions for the selected section", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      sec = make_section(ch, "Transcription")

      make_question(course, %{
        chapter_id: ch.id,
        section_id: sec.id,
        content: "Describe mRNA synthesis."
      })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      html = render_click(view, "select_section", %{"id" => sec.id, "chapter_id" => ch.id})
      assert html =~ "Describe mRNA synthesis."
    end

    test "does not show questions from other sections", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      sec1 = make_section(ch)
      sec2 = make_section(ch)
      make_question(course, %{chapter_id: ch.id, section_id: sec1.id, content: "Sec1 question"})
      make_question(course, %{chapter_id: ch.id, section_id: sec2.id, content: "Sec2 question"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      html = render_click(view, "select_section", %{"id" => sec1.id, "chapter_id" => ch.id})
      assert html =~ "Sec1 question"
      refute html =~ "Sec2 question"
    end
  end

  # ── Role-based visibility ─────────────────────────────────────────────────

  describe "validation status gating" do
    test "student does not see pending/needs_review questions", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      make_question(course, %{chapter_id: ch.id, content: "Visible Q", validation_status: :passed})

      make_question(course, %{
        chapter_id: ch.id,
        content: "Hidden Pending",
        validation_status: :pending
      })

      make_question(course, %{
        chapter_id: ch.id,
        content: "Hidden Review",
        validation_status: :needs_review
      })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_chapter", %{"id" => ch.id})

      assert html =~ "Visible Q"
      refute html =~ "Hidden Pending"
      refute html =~ "Hidden Review"
    end

    test "admin sees all validation statuses by default", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Passed Q", validation_status: :passed})

      make_question(course, %{
        chapter_id: ch.id,
        content: "Pending Q",
        validation_status: :pending
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_chapter", %{"id" => ch.id})

      assert html =~ "Passed Q"
      assert html =~ "Pending Q"
    end

    test "admin sees validation status badge on question cards", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, validation_status: :needs_review})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_chapter", %{"id" => ch.id})

      assert html =~ "Needs_review" or html =~ "needs_review" or html =~ "Needs review"
    end
  end

  # ── Filters ───────────────────────────────────────────────────────────────

  describe "set_filter event" do
    test "filters by difficulty", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Easy Q", difficulty: :easy})
      make_question(course, %{chapter_id: ch.id, content: "Hard Q", difficulty: :hard})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_change(view, "set_filter", %{"difficulty" => "easy", "question_type" => ""})
      assert html =~ "Easy Q"
      refute html =~ "Hard Q"
    end

    test "admin can filter by validation_status", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Passed Q", validation_status: :passed})

      make_question(course, %{
        chapter_id: ch.id,
        content: "Pending Q",
        validation_status: :pending
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{
          "difficulty" => "",
          "question_type" => "",
          "validation_status" => "pending"
        })

      assert html =~ "Pending Q"
      refute html =~ "Passed Q"
    end
  end

  # ── Pagination ────────────────────────────────────────────────────────────

  describe "pagination" do
    test "shows pagination controls when there are more questions than page size", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      # Create page_size + 1 questions
      for _ <- 1..(Questions.page_size() + 1) do
        make_question(course, %{chapter_id: ch.id})
      end

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_chapter", %{"id" => ch.id})

      assert html =~ "Page 1 of 2"
    end

    test "next_page loads next batch", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      for i <- 1..(Questions.page_size() + 1) do
        make_question(course, %{chapter_id: ch.id, content: "Q number #{i}"})
      end

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      html = render_click(view, "next_page", %{})

      assert html =~ "Page 2 of 2"
    end
  end

  # ── Question expand/collapse ──────────────────────────────────────────────

  describe "toggle_question event" do
    test "expands question to show full detail", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      q =
        make_question(course, %{
          chapter_id: ch.id,
          content: "Full content here",
          answer: "The answer"
        })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_click(view, "toggle_question", %{"id" => q.id})
      assert html =~ "The answer"
    end
  end

  # ── Delete question ───────────────────────────────────────────────────────

  describe "delete_question event" do
    test "admin can delete a question", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, content: "To be deleted"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_click(view, "delete_question", %{"id" => q.id})
      refute html =~ "To be deleted"
    end
  end
end

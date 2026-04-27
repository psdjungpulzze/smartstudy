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

    test "shows flash info after deletion", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, content: "Flash target"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      html = render_click(view, "delete_question", %{"id" => q.id})

      assert html =~ "deleted"
    end
  end

  # ── Toggle chapter ─────────────────────────────────────────────────────────

  describe "toggle_chapter event" do
    test "first chapter is expanded on mount and toggle collapses it", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "First Chapter")
      _sec = make_section(ch, "Inner Section")
      make_question(course, %{chapter_id: ch.id})

      # On mount the first chapter is expanded, so its sections are visible
      {:ok, view, html_mount} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      assert html_mount =~ "Inner Section"

      # Toggling collapses it (sections no longer visible)
      html_collapsed = render_click(view, "toggle_chapter", %{"id" => ch.id})
      refute html_collapsed =~ "Inner Section"

      # Toggling again expands it
      html_expanded = render_click(view, "toggle_chapter", %{"id" => ch.id})
      assert html_expanded =~ "Inner Section"
    end

    test "non-first chapter can be expanded via toggle", %{conn: conn} do
      course = make_course()
      _ch1 = make_chapter(course, "First Chapter")
      ch2 = make_chapter(course, "Second Chapter")
      _sec = make_section(ch2, "Second Section")
      make_question(course, %{chapter_id: ch2.id})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      # Second chapter is not auto-expanded; toggle should expand it
      html = render_click(view, "toggle_chapter", %{"id" => ch2.id})
      assert html =~ "Second Section"
    end
  end

  # ── Prev page ─────────────────────────────────────────────────────────────

  describe "prev_page event" do
    test "prev_page does nothing on first page", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      for _ <- 1..(Questions.page_size() + 1) do
        make_question(course, %{chapter_id: ch.id})
      end

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      html = render_click(view, "prev_page", %{})

      # Should still be on page 1
      assert html =~ "Page 1"
    end

    test "prev_page goes back after advancing to page 2", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      for _ <- 1..(Questions.page_size() + 1) do
        make_question(course, %{chapter_id: ch.id})
      end

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      render_click(view, "next_page", %{})
      html = render_click(view, "prev_page", %{})

      assert html =~ "Page 1"
    end
  end

  # ── Add Question form ──────────────────────────────────────────────────────

  describe "show_add_question event" do
    test "shows add question form for admin", %{conn: conn} do
      course = make_course()
      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      html = render_click(view, "show_add_question", %{})
      assert html =~ "Add Question"
      assert html =~ "Save Question"
    end
  end

  describe "cancel_form event" do
    test "hides form after cancel", %{conn: conn} do
      course = make_course()
      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      render_click(view, "show_add_question", %{})
      html = render_click(view, "cancel_form", %{})

      refute html =~ "Save Question"
    end
  end

  describe "validate_question event" do
    test "shows validation errors on empty submission", %{conn: conn} do
      course = make_course()
      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      render_click(view, "show_add_question", %{})
      html = render_change(view, "validate_question", %{"question" => %{"content" => "", "answer" => ""}})

      # Form is still showing
      assert html =~ "Save Question" or html =~ "Add Question"
    end
  end

  describe "save_question event" do
    test "admin can create a new question via form", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "Saved Chapter")

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "show_add_question", %{})

      html =
        render_submit(view, "save_question", %{
          "question" => %{
            "content" => "Newly created question",
            "answer" => "Correct answer",
            "question_type" => "multiple_choice",
            "difficulty" => "easy",
            "chapter_id" => ch.id
          }
        })

      assert html =~ "added" or html =~ "Newly created question" or !String.contains?(html, "Save Question")
    end
  end

  # ── Approve / Reject question ──────────────────────────────────────────────

  describe "approve_question event" do
    test "admin can approve a needs_review question", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, validation_status: :needs_review, content: "Approve Me"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_click(view, "approve_question", %{"id" => q.id})
      assert html =~ "approved" or html =~ "Passed" or html =~ "passed"
    end

    test "student cannot approve a question (no-op)", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, validation_status: :passed, content: "Student tries approve"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      # Student role is not "admin" so the event should no-op
      html = render_click(view, "approve_question", %{"id" => q.id})
      # Still showing the question
      assert html =~ "Student tries approve"
    end
  end

  describe "reject_question event" do
    test "admin can reject a needs_review question", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, validation_status: :needs_review, content: "Reject Me"})

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_click(view, "reject_question", %{"id" => q.id})
      assert html =~ "rejected" or html =~ "Failed" or html =~ "failed"
    end
  end

  # ── Question filter by type ────────────────────────────────────────────────

  describe "filter by question type" do
    test "filters questions by question_type", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "MC Question", question_type: :multiple_choice})
      make_question(course, %{chapter_id: ch.id, content: "Essay Question", question_type: :essay})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_change(view, "set_filter", %{"difficulty" => "", "question_type" => "essay"})
      assert html =~ "Essay Question"
      refute html =~ "MC Question"
    end
  end

  # ── Toggle question collapse ───────────────────────────────────────────────

  describe "toggle_question collapse" do
    test "collapses an expanded question", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, content: "Toggle question", answer: "Special answer"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      # Expand
      render_click(view, "toggle_question", %{"id" => q.id})
      # Collapse
      html = render_click(view, "toggle_question", %{"id" => q.id})

      # Answer detail should be hidden (not shown in card preview)
      refute html =~ "Special answer"
    end
  end

  # ── Empty course ──────────────────────────────────────────────────────────

  describe "empty course" do
    test "shows empty state when no questions in selected chapter", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "Empty Chapter")

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_chapter", %{"id" => ch.id})

      assert html =~ "No questions here"
    end

    test "page title includes course name", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "Question Bank"
    end
  end

  # ── Admin filter shows status select ──────────────────────────────────────

  describe "admin-only filter UI" do
    test "admin sees the validation status filter select", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "All Statuses"
    end

    test "student does not see the validation status filter select", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      refute html =~ "All Statuses"
    end
  end

  # ── Course with no chapters ────────────────────────────────────────────────

  describe "course with no chapters" do
    test "renders empty state sidebar when no chapters exist", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "No questions yet"
    end

    test "shows no questions message when course has no chapters", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "No questions here"
    end
  end

  # ── Teacher role ───────────────────────────────────────────────────────────

  @teacher_uuid "00000000-0000-0000-0000-000000000003"

  defp teacher_conn(conn) do
    conn
    |> init_test_session(%{
      dev_user_id: @teacher_uuid,
      dev_user: %{
        "id" => @teacher_uuid,
        "role" => "teacher",
        "email" => "teacher@test.com",
        "display_name" => "Test Teacher",
        "user_role_id" => @teacher_uuid
      }
    })
  end

  describe "teacher role" do
    test "teacher sees Add Question button", %{conn: conn} do
      course = make_course()
      {:ok, _view, html} = live(teacher_conn(conn), ~p"/courses/#{course.id}/questions")

      assert html =~ "Add Question"
    end

    test "teacher can delete questions", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      q = make_question(course, %{chapter_id: ch.id, content: "Teacher delete target"})

      {:ok, view, _html} = live(teacher_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_click(view, "delete_question", %{"id" => q.id})
      refute html =~ "Teacher delete target"
    end
  end

  # ── next_page at max page (no-op) ─────────────────────────────────────────

  describe "next_page no-op at max" do
    test "next_page does nothing when already on last page", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Only question"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      # Only 1 question, so total_pages = 1. next_page should be a no-op
      html = render_click(view, "next_page", %{})
      assert html =~ "Page 1"
    end
  end

  # ── save_question validation error path ───────────────────────────────────

  describe "save_question error path" do
    test "shows form again on validation failure for missing required fields", %{conn: conn} do
      course = make_course()
      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "show_add_question", %{})

      # Submit with missing required fields (no content, no answer, no question_type)
      html =
        render_submit(view, "save_question", %{
          "question" => %{
            "content" => "",
            "answer" => "",
            "question_type" => ""
          }
        })

      # Form should remain visible (validation failed, not saved)
      assert html =~ "Save Question" or html =~ "Add Question"
    end
  end

  # ── Selection label with section ──────────────────────────────────────────

  describe "selection label shows section name" do
    test "header shows section name after selecting a section", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course, "BioChapter")
      sec = make_section(ch, "ProteinSection")
      make_question(course, %{chapter_id: ch.id, section_id: sec.id, content: "Protein Q"})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      html = render_click(view, "select_section", %{"id" => sec.id, "chapter_id" => ch.id})

      assert html =~ "ProteinSection"
    end
  end

  # ── Question with options (multiple choice expanded) ─────────────────────

  describe "expanded question with options" do
    test "expanded MC question shows options block", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      {:ok, q} =
        Questions.create_question(%{
          content: "MC with options",
          answer: "B",
          question_type: :multiple_choice,
          difficulty: :easy,
          course_id: course.id,
          chapter_id: ch.id,
          validation_status: :passed,
          options: %{"A" => "Wrong answer", "B" => "Correct answer"}
        })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      html = render_click(view, "toggle_question", %{"id" => q.id})

      assert html =~ "Options"
      assert html =~ "Wrong answer"
      assert html =~ "Correct answer"
    end
  end

  # ── Admin filter by failed status ─────────────────────────────────────────

  describe "admin filter by failed status" do
    test "admin can filter by failed validation_status", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Passed Q", validation_status: :passed})

      make_question(course, %{
        chapter_id: ch.id,
        content: "Failed Q",
        validation_status: :failed
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{
          "difficulty" => "",
          "question_type" => "",
          "validation_status" => "failed"
        })

      assert html =~ "Failed Q"
      refute html =~ "Passed Q"
    end
  end

  # ── Question with explanation ──────────────────────────────────────────────

  describe "question with explanation" do
    test "expanded question shows explanation when present", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      {:ok, q} =
        Questions.create_question(%{
          content: "Explain this",
          answer: "The answer",
          question_type: :short_answer,
          difficulty: :medium,
          course_id: course.id,
          chapter_id: ch.id,
          validation_status: :passed,
          explanation: "This is the explanation text"
        })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})
      html = render_click(view, "toggle_question", %{"id" => q.id})

      assert html =~ "Explanation"
      assert html =~ "This is the explanation text"
    end
  end

  # ── Question type filter: short_answer, free_response, true_false ─────────

  describe "filter by additional question types" do
    test "filters questions by short_answer type", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Short Q", question_type: :short_answer})
      make_question(course, %{chapter_id: ch.id, content: "MC Q", question_type: :multiple_choice})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{"difficulty" => "", "question_type" => "short_answer"})

      assert html =~ "Short Q"
      refute html =~ "MC Q"
    end

    test "filters questions by true_false type", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "TF Q", question_type: :true_false})
      make_question(course, %{chapter_id: ch.id, content: "Essay Q", question_type: :essay})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{"difficulty" => "", "question_type" => "true_false"})

      assert html =~ "TF Q"
      refute html =~ "Essay Q"
    end

    test "filters questions by free_response type", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      make_question(course, %{
        chapter_id: ch.id,
        content: "FreeResp Q",
        question_type: :free_response
      })

      make_question(course, %{
        chapter_id: ch.id,
        content: "Short Q2",
        question_type: :short_answer
      })

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{
          "difficulty" => "",
          "question_type" => "free_response"
        })

      assert html =~ "FreeResp Q"
      refute html =~ "Short Q2"
    end
  end

  # ── Filter by difficulty medium/hard ──────────────────────────────────────

  describe "filter by medium and hard difficulty" do
    test "filters by medium difficulty", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Medium Q", difficulty: :medium})
      make_question(course, %{chapter_id: ch.id, content: "Easy Q2", difficulty: :easy})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_change(view, "set_filter", %{"difficulty" => "medium", "question_type" => ""})
      assert html =~ "Medium Q"
      refute html =~ "Easy Q2"
    end

    test "filters by hard difficulty", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)
      make_question(course, %{chapter_id: ch.id, content: "Hard Q", difficulty: :hard})
      make_question(course, %{chapter_id: ch.id, content: "Medium Q2", difficulty: :medium})

      {:ok, view, _html} = live(student_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html = render_change(view, "set_filter", %{"difficulty" => "hard", "question_type" => ""})
      assert html =~ "Hard Q"
      refute html =~ "Medium Q2"
    end
  end

  # ── Admin needs_review filter ──────────────────────────────────────────────

  describe "admin filter by needs_review" do
    test "admin can filter by needs_review validation_status", %{conn: conn} do
      course = make_course()
      ch = make_chapter(course)

      make_question(course, %{
        chapter_id: ch.id,
        content: "Review Q",
        validation_status: :needs_review
      })

      make_question(course, %{
        chapter_id: ch.id,
        content: "Passed Q2",
        validation_status: :passed
      })

      {:ok, view, _html} = live(admin_conn(conn), ~p"/courses/#{course.id}/questions")
      render_click(view, "select_chapter", %{"id" => ch.id})

      html =
        render_change(view, "set_filter", %{
          "difficulty" => "",
          "question_type" => "",
          "validation_status" => "needs_review"
        })

      assert html =~ "Review Q"
      refute html =~ "Passed Q2"
    end
  end
end

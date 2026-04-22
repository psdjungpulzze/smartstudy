defmodule FunSheepWeb.AssessmentLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.ContentFixtures

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "user_role_id" => user_role.id
      }
    })
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{created_by_id: user_role.id})

    {:ok, chapter} =
      FunSheep.Courses.create_chapter(%{name: "Chapter 1", position: 1, course_id: course.id})

    {:ok, section} =
      FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: chapter.id})

    {:ok, _q1} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "What is the powerhouse of the cell?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Mitochondria", "B" => "Nucleus", "C" => "Ribosome", "D" => "Golgi"},
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    {:ok, _q2} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "DNA stands for?",
        answer: "B",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{
          "A" => "Deoxyribonucleic Acid Test",
          "B" => "Deoxyribonucleic Acid",
          "C" => "Ribonucleic Acid",
          "D" => "None"
        },
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    {:ok, _q3} =
      FunSheep.Questions.create_question(%{
        validation_status: :passed,
        content: "Cells divide via?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{
          "A" => "Mitosis",
          "B" => "Osmosis",
          "C" => "Diffusion",
          "D" => "Photosynthesis"
        },
        course_id: course.id,
        chapter_id: chapter.id,
        section_id: section.id,
        classification_status: :admin_reviewed
      })

    {:ok, schedule} =
      FunSheep.Assessments.create_test_schedule(%{
        name: "Bio Quiz",
        test_date: Date.add(Date.utc_today(), 7),
        scope: %{"chapter_ids" => [chapter.id]},
        user_role_id: user_role.id,
        course_id: course.id
      })

    %{user_role: user_role, course: course, chapter: chapter, schedule: schedule}
  end

  describe "assessment flow" do
    test "starts and shows a question", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      assert html =~ "Bio Quiz"
      assert html =~ "Question 1"
      # Should show one of the question contents
      assert html =~ "powerhouse" or html =~ "DNA" or html =~ "Cells divide"
    end

    test "shows feedback after answering", %{conn: conn, user_role: ur, schedule: schedule} do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      # Select an answer
      render_click(view, "select_answer", %{"answer" => "A"})

      # Submit the answer
      html = render_click(view, "submit_answer")

      # Should show feedback (either correct or incorrect)
      assert html =~ "Correct" or html =~ "Incorrect"
      assert html =~ "Next Question"
    end

    test "advances to next question after feedback", %{
      conn: conn,
      user_role: ur,
      schedule: schedule
    } do
      conn = auth_conn(conn, ur)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{schedule.course_id}/tests/#{schedule.id}/assess")

      # Answer first question
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")

      # Click next
      html = render_click(view, "next_question")

      # Should show question 2
      assert html =~ "Question 2"
    end

    test "shows honest empty state when no questions match scope", %{
      conn: conn,
      user_role: ur,
      course: course
    } do
      # Regression: a schedule whose chapters have no questions must NOT
      # render a zero-of-zero "Assessment Complete" summary (which would
      # advance the study path past Assessment despite no answers). The
      # readiness gate now blocks mount entirely; the specific copy depends
      # on course status (here: default "pending" → "Course is still
      # processing").
      {:ok, empty_chapter} =
        FunSheep.Courses.create_chapter(%{
          name: "Empty Chapter",
          position: 99,
          course_id: course.id
        })

      {:ok, empty_schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Empty Scope",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [empty_chapter.id]},
          user_role_id: ur.id,
          course_id: course.id
        })

      conn = auth_conn(conn, ur)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{empty_schedule.course_id}/tests/#{empty_schedule.id}/assess")

      assert html =~ "Course is still processing"
      refute html =~ "Assessment Complete"
      refute html =~ "Question 1"
      assert html =~ ~s|href="/courses/#{course.id}"|
    end
  end

  describe "readiness gating" do
    defp ready_course(user_role) do
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, course} =
        course
        |> FunSheep.Courses.Course.changeset(%{processing_status: "ready"})
        |> FunSheep.Repo.update()

      course
    end

    defp passed_classified(course, chapter, section, idx) do
      {:ok, _} =
        FunSheep.Questions.create_question(%{
          validation_status: :passed,
          content: "R#{idx}",
          answer: "A",
          question_type: :multiple_choice,
          difficulty: :medium,
          options: %{"A" => "a", "B" => "b"},
          course_id: course.id,
          chapter_id: chapter.id,
          section_id: section.id,
          classification_status: :ai_classified
        })
    end

    test "shows scope_empty screen with Generate Questions Now button when course is ready but scope has none",
         %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ready_course(user_role)

      {:ok, empty_chapter} =
        FunSheep.Courses.create_chapter(%{name: "Empty", position: 1, course_id: course.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Readiness Test",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [empty_chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      assert html =~ "No questions for the selected chapters"
      assert html =~ "Generate Questions Now"
      refute html =~ "Question 1"
    end

    test "shows scope_partial screen when some chapters ready and some missing", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ready_course(user_role)

      {:ok, ready_chapter} =
        FunSheep.Courses.create_chapter(%{name: "Ready", position: 1, course_id: course.id})

      {:ok, section} =
        FunSheep.Courses.create_section(%{name: "S", position: 1, chapter_id: ready_chapter.id})

      for i <- 1..3, do: passed_classified(course, ready_chapter, section, i)

      {:ok, missing_chapter} =
        FunSheep.Courses.create_chapter(%{name: "Missing", position: 2, course_id: course.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Partial",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [ready_chapter.id, missing_chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      assert html =~ "Some chapters still need questions"
      assert html =~ "Generate Questions Now"
    end

    test "shows course_failed screen when course processing failed", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, course} =
        course
        |> FunSheep.Courses.Course.changeset(%{
          processing_status: "failed",
          processing_step: "AI service unavailable"
        })
        |> FunSheep.Repo.update()

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Failed",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      assert html =~ "Course processing failed"
      assert html =~ "AI service unavailable"
      refute html =~ "Generate Questions Now"
    end

    test "course_not_ready screen humanizes the processing stage", %{conn: conn} do
      user_role = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user_role.id})

      {:ok, course} =
        course
        |> FunSheep.Courses.Course.changeset(%{processing_status: "validating"})
        |> FunSheep.Repo.update()

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Stage",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, _view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      assert html =~ "Course is still processing"
      assert html =~ "validating questions"
    end

    test "retry_generation event enqueues gen for missing chapters without crashing", %{
      conn: conn
    } do
      user_role = ContentFixtures.create_user_role()
      course = ready_course(user_role)

      {:ok, empty_chapter} =
        FunSheep.Courses.create_chapter(%{name: "Empty", position: 1, course_id: course.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Retry",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [empty_chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, view, _html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      # Button is rendered and clickable; event handler must not crash
      assert render_click(view, "retry_generation") =~ "No questions for the selected chapters"
    end

    test "PubSub {:questions_ready, ...} transitions the view when scope becomes ready", %{
      conn: conn
    } do
      user_role = ContentFixtures.create_user_role()
      course = ready_course(user_role)

      {:ok, chapter} =
        FunSheep.Courses.create_chapter(%{name: "Ch", position: 1, course_id: course.id})

      {:ok, section} =
        FunSheep.Courses.create_section(%{name: "S", position: 1, chapter_id: chapter.id})

      {:ok, schedule} =
        FunSheep.Assessments.create_test_schedule(%{
          name: "Live Transition",
          test_date: Date.add(Date.utc_today(), 7),
          scope: %{"chapter_ids" => [chapter.id]},
          user_role_id: user_role.id,
          course_id: course.id
        })

      conn = auth_conn(conn, user_role)

      {:ok, view, html} =
        live(conn, ~p"/courses/#{course.id}/tests/#{schedule.id}/assess")

      assert html =~ "No questions for the selected chapters"

      # Simulate the generation pipeline finishing: create passed+classified
      # questions for the chapter, then broadcast the signal workers emit.
      for i <- 1..3, do: passed_classified(course, chapter, section, i)

      Phoenix.PubSub.broadcast(
        FunSheep.PubSub,
        "course:#{course.id}",
        {:questions_ready, %{chapter_ids: [chapter.id]}}
      )

      # Wait for the LiveView process to handle the broadcast
      html = render(view)
      assert html =~ "Question 1"
      refute html =~ "No questions for the selected chapters"
    end
  end
end

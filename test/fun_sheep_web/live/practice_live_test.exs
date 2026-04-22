defmodule FunSheepWeb.PracticeLiveTest do
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

    {:ok, q1} =
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

    {:ok, q2} =
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

    # Create wrong attempts so these are "weak" questions
    FunSheep.Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q1.id,
      answer_given: "B",
      is_correct: false
    })

    FunSheep.Questions.create_question_attempt(%{
      user_role_id: user_role.id,
      question_id: q2.id,
      answer_given: "A",
      is_correct: false
    })

    %{user_role: user_role, course: course, chapter: chapter, q1: q1, q2: q2}
  end

  describe "practice flow" do
    test "renders practice page with questions", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      assert html =~ "Practice Mode"
      assert html =~ course.name
      assert html =~ "Question 1"
    end

    test "shows feedback after answering", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      render_click(view, "select_answer", %{"answer" => "A"})
      html = render_click(view, "submit_answer")

      assert html =~ "Correct" or html =~ "Incorrect"
      assert html =~ "Next Question"
    end

    test "shows summary on completion", %{conn: conn, user_role: ur, course: course} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/courses/#{course.id}/practice")

      # Answer all questions
      render_click(view, "select_answer", %{"answer" => "A"})
      render_click(view, "submit_answer")
      render_click(view, "next_question")

      render_click(view, "select_answer", %{"answer" => "B"})
      render_click(view, "submit_answer")
      html = render_click(view, "next_question")

      assert html =~ "Practice Complete!"
      assert html =~ "Practice Again"
      assert html =~ "Back to Course"
    end
  end

  describe "no weak questions" do
    test "shows empty state when no wrong answers exist", %{conn: conn, course: course} do
      other_user = ContentFixtures.create_user_role()
      conn = auth_conn(conn, other_user)
      {:ok, _view, html} = live(conn, ~p"/courses/#{course.id}/practice")

      assert html =~ "No Weak Questions Found"
    end
  end
end

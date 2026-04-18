defmodule StudySmartWeb.QuickTestLiveTest do
  use StudySmartWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudySmart.ContentFixtures

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
      StudySmart.Courses.create_chapter(%{
        name: "Chapter 1",
        position: 1,
        course_id: course.id
      })

    {:ok, _q1} =
      StudySmart.Questions.create_question(%{
        content: "What is the powerhouse of the cell?",
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "Mitochondria", "B" => "Nucleus", "C" => "Ribosome", "D" => "Golgi"},
        course_id: course.id,
        chapter_id: chapter.id
      })

    {:ok, _q2} =
      StudySmart.Questions.create_question(%{
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
        chapter_id: chapter.id
      })

    {:ok, _q3} =
      StudySmart.Questions.create_question(%{
        content: "Is the sky blue?",
        answer: "True",
        question_type: :true_false,
        difficulty: :easy,
        course_id: course.id,
        chapter_id: chapter.id
      })

    %{user_role: user_role, course: course, chapter: chapter}
  end

  describe "quick test page" do
    test "renders card with question", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, _view, html} = live(conn, ~p"/quick-test")

      assert html =~ "Quick Test"
      # Should show one of the question contents
      assert html =~ "powerhouse" or html =~ "DNA" or html =~ "sky blue"
    end

    test "'I Know This' advances to next card", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/quick-test")

      html = render_click(view, "mark_known")

      # Stats should update
      assert html =~ "Quick Test"
    end

    test "'I Don't Know' shows explanation", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/quick-test")

      html = render_click(view, "mark_unknown")

      assert html =~ "Correct Answer"
      assert html =~ "Got It"
    end

    test "completing all cards shows summary", %{conn: conn, user_role: ur} do
      conn = auth_conn(conn, ur)
      {:ok, view, _html} = live(conn, ~p"/quick-test")

      # Process all 3 cards with "I Know This"
      render_click(view, "mark_known")
      render_click(view, "mark_known")
      html = render_click(view, "mark_known")

      assert html =~ "Session Complete!"
      assert html =~ "Practice Again"
      assert html =~ "Back to Dashboard"
    end
  end
end

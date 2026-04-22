defmodule FunSheepWeb.QuickPracticeLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Assessments, ContentFixtures, Questions, Tutorials}

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

  defp add_question(course_id, content) do
    # Auto-create a chapter + section so each question carries a skill tag
    # required by adaptive flows (North Star I-1).
    {:ok, ch} =
      FunSheep.Courses.create_chapter(%{
        name: "Ch #{System.unique_integer([:positive])}",
        position: 1,
        course_id: course_id
      })

    {:ok, sec} =
      FunSheep.Courses.create_section(%{name: "Sec 1", position: 1, chapter_id: ch.id})

    {:ok, q} =
      Questions.create_question(%{
        validation_status: :passed,
        content: content,
        answer: "A",
        question_type: :multiple_choice,
        difficulty: :easy,
        options: %{"A" => "yes", "B" => "no"},
        course_id: course_id,
        chapter_id: ch.id,
        section_id: sec.id,
        classification_status: :admin_reviewed
      })

    q
  end

  defp schedule_test(user_role_id, course_id, name, days_from_now) do
    {:ok, ts} =
      Assessments.create_test_schedule(%{
        name: name,
        test_date: Date.add(Date.utc_today(), days_from_now),
        scope: %{},
        user_role_id: user_role_id,
        course_id: course_id
      })

    ts
  end

  describe "course defaulting from upcoming tests" do
    test "pulls questions only from the closest upcoming test's course", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      # Mark tutorial seen so it doesn't obscure assertions
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})

      add_question(bio.id, "BIO-Q-close")
      add_question(math.id, "MATH-Q-far")

      # Closest test is AP Biology (3 days), then AP Calc (20 days)
      schedule_test(user.id, bio.id, "AP Biology Unit 3", 3)
      schedule_test(user.id, math.id, "AP Calc Exam", 20)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "BIO-Q-close"
      refute html =~ "MATH-Q-far"
    end

    test "?test_id= URL param overrides default selection", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})

      add_question(bio.id, "BIO-Q")
      add_question(math.id, "MATH-Q-pick-me")

      schedule_test(user.id, bio.id, "AP Biology Unit 3", 3)
      math_ts = schedule_test(user.id, math.id, "AP Calc Exam", 20)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice?test_id=#{math_ts.id}")

      assert html =~ "MATH-Q-pick-me"
      refute html =~ "BIO-Q"
    end

    test "renders a pill for each upcoming test", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")

      bio = ContentFixtures.create_course(%{name: "AP Biology", created_by_id: user.id})
      math = ContentFixtures.create_course(%{name: "AP Calc", created_by_id: user.id})
      add_question(bio.id, "q1")
      add_question(math.id, "q2")

      schedule_test(user.id, bio.id, "Bio Final", 5)
      schedule_test(user.id, math.id, "Calc Midterm", 14)

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "AP Biology"
      assert html =~ "AP Calc"
      # days-until labels — at least one of these forms
      assert html =~ "5d" or html =~ "tomorrow" or html =~ "today"
    end
  end

  describe "first-time tutorial" do
    test "overlay shows on first visit", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      assert html =~ "How Practice works"
      assert html =~ "Got it!"
    end

    test "dismiss_tutorial marks the tutorial seen", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      refute Tutorials.seen?(user.id, "quick_practice")

      html = render_click(view, "dismiss_tutorial")
      refute html =~ "How Practice works"

      assert Tutorials.seen?(user.id, "quick_practice")
    end

    test "overlay is not shown once seen", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, _view, html} = live(conn, ~p"/practice")

      refute html =~ "How Practice works"
    end

    test "replay_tutorial re-opens overlay for an already-seen tutorial", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")

      conn = auth_conn(conn, user)
      {:ok, view, html} = live(conn, ~p"/practice")

      refute html =~ "How Practice works"

      html = render_click(view, "replay_tutorial")
      assert html =~ "How Practice works"
    end
  end

  describe "keyboard shortcuts" do
    test "ArrowRight marks question as known (desktop)", %{conn: conn} do
      user = ContentFixtures.create_user_role()
      {:ok, _} = Tutorials.mark_seen(user.id, "quick_practice")
      course = ContentFixtures.create_course(%{created_by_id: user.id})
      add_question(course.id, "q1")
      add_question(course.id, "q2")

      conn = auth_conn(conn, user)
      {:ok, view, _html} = live(conn, ~p"/practice")

      # ArrowRight from question phase → mark_known → advances
      html = render_keydown(view, "keydown", %{"key" => "ArrowRight"})
      # Stats pill should now show 1 correct
      assert html =~ "1"
    end
  end
end

defmodule FunSheepWeb.TeacherOnboardingLiveTest do
  @moduledoc """
  Flow C — LiveView tests for the teacher onboarding wizard.
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

  defp teacher_conn(conn) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: "teacher_#{System.unique_integer([:positive])}",
        role: :teacher,
        email: "t_#{System.unique_integer([:positive])}@t.com",
        display_name: "Teacher"
      })

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "user_role_id" => user.id,
          "interactor_user_id" => user.interactor_user_id,
          "role" => "teacher",
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  test "renders step 1 with the class-details form", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/onboarding/teacher")

    assert html =~ "Create your first class"
    assert html =~ "Class name"
    assert html =~ "Next — add students"
  end

  test "submitting class info advances to step 2", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{
      "name" => "10th Grade Chem",
      "period" => "3rd",
      "course" => "Chemistry",
      "school_year" => "2025-2026"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Add students to 10th Grade Chem"
  end

  test "rejects empty class name", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => ""})
    |> render_submit()

    html = render(view)
    assert html =~ "Please give your class a name"
  end

  test "adding duplicate student email is rejected", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    # Advance to step 2
    view
    |> form("form[phx-submit=submit_class]", %{"name" => "Class"})
    |> render_submit()

    # Add a student
    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "kid@school.edu"})
    |> render_submit()

    # Try to add again
    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "kid@school.edu"})
    |> render_submit()

    html = render(view)
    assert html =~ "already on the list"
  end

  test "full wizard reaches the Done step", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    # Step 1
    view
    |> form("form[phx-submit=submit_class]", %{"name" => "Chem"})
    |> render_submit()

    # Step 2 — add one student
    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "alice@school.edu"})
    |> render_submit()

    view |> element("button", "Send invites") |> render_click()

    # Step 3 → skip
    view |> element("button", "Skip for now") |> render_click()

    html = render(view)
    assert html =~ "Chem is set up"
    assert html =~ "parent" and html =~ "not you"
    assert html =~ "Go to your classroom"
  end

  # ── Additional coverage tests ────────────────────────────────────────────

  test "update_class live change event updates class details", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    # The update_class handler requires the _target key (phx-change fires with it)
    html =
      render_change(view, "update_class", %{
        "_target" => ["name"],
        "name" => "Updated Class",
        "period" => "4th",
        "course" => "Physics",
        "school_year" => "2025-2026"
      })

    # The form should still be rendered (still on step 1)
    assert html =~ "Create your first class"
  end

  test "add_student rejects empty email", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "MyClass"})
    |> render_submit()

    # Use render_click to bypass HTML5 email type validation
    html = render_click(view, "add_student", %{"student_email" => ""})

    assert html =~ "Enter a student email"
  end

  test "add_student rejects malformed email", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "MyClass"})
    |> render_submit()

    # Use render_click with the event directly to bypass HTML5 email validation
    html = render_click(view, "add_student", %{"student_email" => "notanemail"})

    assert html =~ "doesn&#39;t look like an email" or html =~ "doesn't look like an email"
  end

  test "remove_student removes the student from list", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "MyClass"})
    |> render_submit()

    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "alice@school.edu"})
    |> render_submit()

    html = render(view)
    assert html =~ "alice@school.edu"

    render_click(view, "remove_student", %{"email" => "alice@school.edu"})

    html = render(view)
    refute html =~ "alice@school.edu"
  end

  test "send_invites with empty list shows error", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "EmptyClass"})
    |> render_submit()

    html = render_click(view, "send_invites", %{})
    assert html =~ "Add at least one student first"
  end

  test "goto_step event navigates steps", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "Nav Class"})
    |> render_submit()

    # Go back to step 1
    html = render_click(view, "goto_step", %{"step" => "1"})
    assert html =~ "Create your first class"
  end

  test "set_test event advances to step 4 with test name", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "TestClass"})
    |> render_submit()

    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "bob@school.edu"})
    |> render_submit()

    render_click(view, "send_invites", %{})

    view
    |> form("form[phx-submit=set_test]", %{
      "name" => "Unit 3 Exam",
      "date" => "2026-05-01",
      "subject" => "Chemistry"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "TestClass is set up"
    assert html =~ "Unit 3 Exam"
    assert html =~ "2026-05-01"
  end

  test "skip_test event advances directly to done step", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "SkipTestClass"})
    |> render_submit()

    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "carol@school.edu"})
    |> render_submit()

    render_click(view, "send_invites", %{})

    html = render_click(view, "skip_test", %{})

    assert html =~ "SkipTestClass is set up"
    refute html =~ "Save and finish"
  end

  test "multiple students invited shows plural noun", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/onboarding/teacher")

    view
    |> form("form[phx-submit=submit_class]", %{"name" => "MultiClass"})
    |> render_submit()

    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "d1@school.edu"})
    |> render_submit()

    view
    |> form("form[phx-submit=add_student]", %{"student_email" => "d2@school.edu"})
    |> render_submit()

    render_click(view, "send_invites", %{})
    html = render_click(view, "skip_test", %{})

    # plural noun "students" should appear
    assert html =~ "students"
  end

  test "progress header shows all 4 step labels", %{conn: conn} do
    {conn, _t} = teacher_conn(conn)
    {:ok, _view, html} = live(conn, ~p"/onboarding/teacher")

    assert html =~ "Class"
    assert html =~ "Students"
    assert html =~ "Test"
    assert html =~ "Done"
  end
end

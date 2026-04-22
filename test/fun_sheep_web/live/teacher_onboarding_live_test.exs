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
end

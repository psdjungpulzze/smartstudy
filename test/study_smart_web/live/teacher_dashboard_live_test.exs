defmodule StudySmartWeb.TeacherDashboardLiveTest do
  use StudySmartWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StudySmart.Accounts

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, user_role} = Accounts.create_user_role(Map.merge(defaults, attrs))
    user_role
  end

  defp auth_conn(conn, user_role) do
    role_str = to_string(user_role.role)

    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "role" => role_str,
        "email" => user_role.email,
        "display_name" => user_role.display_name,
        "interactor_user_id" => user_role.interactor_user_id
      }
    })
  end

  describe "teacher with no students" do
    test "shows empty state message", %{conn: conn} do
      teacher = create_user_role(%{role: :teacher, display_name: "Test Teacher"})
      conn = auth_conn(conn, teacher)

      {:ok, _view, html} = live(conn, ~p"/teacher")

      assert html =~ "No students linked yet"
      assert html =~ "Add students to start monitoring their progress"
      assert html =~ "Add Students"
    end
  end

  describe "teacher with students" do
    test "shows student table", %{conn: conn} do
      teacher = create_user_role(%{role: :teacher, display_name: "Test Teacher"})

      student =
        create_user_role(%{
          role: :student,
          display_name: "Bob Student",
          grade: "9th"
        })

      {:ok, sg} = Accounts.invite_guardian(teacher.id, student.email, :teacher)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      conn = auth_conn(conn, teacher)
      {:ok, _view, html} = live(conn, ~p"/teacher")

      assert html =~ "Bob Student"
      assert html =~ student.email
      assert html =~ "9th"
      assert html =~ "Total Students"
      # Should show 1 student count
      assert html =~ ">1</p>"
    end
  end
end

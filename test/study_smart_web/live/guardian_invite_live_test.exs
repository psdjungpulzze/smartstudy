defmodule StudySmartWeb.GuardianInviteLiveTest do
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
    role_str =
      case user_role.role do
        :parent -> "parent"
        :teacher -> "teacher"
        :student -> "student"
      end

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

  describe "parent view" do
    test "parent sees invite form", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      conn = auth_conn(conn, parent)

      {:ok, _view, html} = live(conn, ~p"/guardians")

      assert html =~ "Invite a Student"
      assert html =~ "Send Invite"
    end

    test "parent can invite a student", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, parent)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form", %{email: student.email})
        |> render_submit()

      assert html =~ "Invitation sent!"
    end

    test "parent sees error for nonexistent student email", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      conn = auth_conn(conn, parent)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form", %{email: "nobody@test.com"})
        |> render_submit()

      assert html =~ "No student found with that email"
    end
  end

  describe "student view" do
    test "student sees pending invitations", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      {:ok, _sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      conn = auth_conn(conn, student)
      {:ok, _view, html} = live(conn, ~p"/guardians")

      assert html =~ "Test Parent"
      assert html =~ "Accept"
      assert html =~ "Reject"
    end

    test "student can accept an invitation", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      conn = auth_conn(conn, student)
      {:ok, view, _html} = live(conn, ~p"/guardians")

      # Use render_click with event name and value directly
      html = render_click(view, "accept", %{"id" => sg.id})

      assert html =~ "My Guardians"
      # After accepting, the parent should appear in active guardians
      assert html =~ "Test Parent"
    end
  end
end

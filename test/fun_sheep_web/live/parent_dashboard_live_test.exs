defmodule FunSheepWeb.ParentDashboardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts

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

  describe "parent with no children" do
    test "shows empty state message", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      conn = auth_conn(conn, parent)

      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "No children linked yet"
      assert html =~ "Add a child to start monitoring their progress"
      assert html =~ "Add Child"
    end
  end

  describe "parent with children" do
    test "shows child cards", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})

      student =
        create_user_role(%{
          role: :student,
          display_name: "Alice Student",
          grade: "10th"
        })

      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      conn = auth_conn(conn, parent)
      {:ok, _view, html} = live(conn, ~p"/parent")

      assert html =~ "Alice Student"
      assert html =~ "Grade: 10th"
      assert html =~ "No assessments yet"
      assert html =~ "View Details"
    end
  end
end

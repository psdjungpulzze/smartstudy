defmodule FunSheepWeb.ParentDashboardPhase3Test do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Accountability, Accounts}

  defp user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "u_#{System.unique_integer([:positive])}@t.com",
      display_name: "X"
    }

    {:ok, u} = Accounts.create_user_role(Map.merge(defaults, attrs))
    u
  end

  defp auth(conn, u) do
    conn
    |> init_test_session(%{
      dev_user_id: u.interactor_user_id,
      dev_user: %{
        "id" => u.interactor_user_id,
        "role" => to_string(u.role),
        "email" => u.email,
        "display_name" => u.display_name,
        "interactor_user_id" => u.interactor_user_id
      }
    })
  end

  defp link!(parent, student) do
    {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
    {:ok, _} = Accounts.accept_guardian_invite(sg.id)
    :ok
  end

  test "parent can propose a goal via the dashboard", %{conn: conn} do
    parent = user_role(%{role: :parent, display_name: "P"})
    student = user_role(%{role: :student, display_name: "S", grade: "10"})
    link!(parent, student)

    conn = auth(conn, parent)
    {:ok, view, _html} = live(conn, ~p"/parent")

    # Open propose form
    html = render_click(view, "open_propose_goal", %{})
    assert html =~ "Goal type"

    # Submit
    render_submit(view, "propose_goal", %{
      "student_id" => student.id,
      "goal_type" => "daily_minutes",
      "target_value" => "30",
      "end_date" => ""
    })

    [goal] = Accountability.list_goals_for_student(student.id)
    assert goal.status == :proposed
    assert goal.proposed_by == :guardian
    assert goal.target_value == 30
  end

  test "parent can accept a student-proposed goal via the dashboard", %{conn: conn} do
    parent = user_role(%{role: :parent, display_name: "P"})
    student = user_role(%{role: :student, display_name: "S", grade: "10"})
    link!(parent, student)

    # Student proposes (simulate by flipping proposed_by after a guardian-proposed seed)
    {:ok, goal} =
      Accountability.propose_goal(parent.id, %{
        student_id: student.id,
        goal_type: "daily_minutes",
        target_value: 30,
        start_date: Date.utc_today()
      })

    {:ok, _} =
      goal
      |> Ecto.Changeset.change(%{proposed_by: :student})
      |> FunSheep.Repo.update()

    conn = auth(conn, parent)
    {:ok, view, html} = live(conn, ~p"/parent")
    assert html =~ "Awaiting your response"

    render_click(view, "accept_goal", %{"goal-id" => goal.id})

    updated = FunSheep.Repo.get!(FunSheep.Accountability.StudyGoal, goal.id)
    assert updated.status == :active
  end
end

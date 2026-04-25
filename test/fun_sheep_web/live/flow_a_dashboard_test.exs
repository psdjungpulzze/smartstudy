defmodule FunSheepWeb.FlowADashboardTest do
  @moduledoc """
  LiveView tests for the Flow A student surfaces embedded on `/dashboard`:
  usage meter, Ask card, request-builder modal, waiting card.
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, Billing}

  defp student_conn(conn, attrs \\ %{}) do
    defaults = %{
      interactor_user_id: "student_#{System.unique_integer([:positive])}",
      role: :student,
      email: "s_#{System.unique_integer([:positive])}@t.com",
      display_name: "Kid"
    }

    {:ok, user} = Accounts.create_user_role(Map.merge(defaults, attrs))

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "role" => "student",
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  defp create_parent do
    {:ok, p} =
      Accounts.create_user_role(%{
        interactor_user_id: "parent_#{System.unique_integer([:positive])}",
        role: :parent,
        email: "p_#{System.unique_integer([:positive])}@t.com",
        display_name: "Mom"
      })

    p
  end

  defp link_parent(parent, student) do
    {:ok, _} =
      Accounts.create_student_guardian(%{
        guardian_id: parent.id,
        student_id: student.id,
        relationship_type: :parent,
        status: :active,
        invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    :ok
  end

  defp record_tests(user_role_id, count) do
    for _ <- 1..count do
      {:ok, _} = Billing.record_test_usage(user_role_id, "quick_test")
    end
  end

  describe "usage meter rendering" do
    test "fresh state — 0 of 50 shows positive copy", %{conn: conn} do
      {conn, _user} = student_conn(conn)
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "free practice left this week"
      assert html =~ "0 of 50 this week"
      refute html =~ "Ask a grown-up"
    end

    test "ask state — 43 of 50 renders the Ask card if a guardian is linked", %{conn: conn} do
      {conn, user} = student_conn(conn)
      parent = create_parent()
      link_parent(parent, user)
      record_tests(user.id, 43)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "ask a grown-up" or html =~ "Ask a grown-up"
      assert html =~ "Almost at your weekly free practice"
    end

    test "hardwall state — 50 of 50 shows the complete-for-the-week copy", %{conn: conn} do
      {conn, user} = student_conn(conn)
      parent = create_parent()
      link_parent(parent, user)
      record_tests(user.id, 50)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "Weekly practice complete"
    end

    test "ask state without linked guardian shows the invite-a-grown-up fallback", %{conn: conn} do
      {conn, user} = student_conn(conn)
      record_tests(user.id, 49)

      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "No grown-up linked yet"
      assert html =~ "/guardians"
    end
  end

  # Ask modal interactions are exercised via context-level tests
  # (`FunSheep.PracticeRequestsTest`) and will be verified in the
  # end-to-end visual testing pass before PR 3 merges.
end

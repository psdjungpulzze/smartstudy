defmodule FunSheepWeb.GuardianInviteLiveTest do
  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

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
        |> form("form[phx-submit=\"invite\"]", %{email: student.email})
        |> render_submit()

      assert html =~ "Invitation sent!"
    end

    test "parent sees error for nonexistent student email", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Test Parent"})
      conn = auth_conn(conn, parent)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "nobody@test.com"})
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

    test "student sees the invite form", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, _view, html} = live(conn, ~p"/guardians")

      assert html =~ "Invite a grown-up"
      assert html =~ "Send invite"
      assert html =~ "grown-up@example.com"
    end

    test "student inviting a parent with an existing account creates pending link", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})

      _parent =
        create_user_role(%{role: :parent, display_name: "Mom", email: "mom@example.com"})

      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "mom@example.com"})
        |> render_submit()

      assert html =~ "Invitation sent"
      assert html =~ "They already have a FunSheep account"
    end

    test "student inviting an unknown email dispatches the invite email", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "stranger@example.com"})
        |> render_submit()

      assert html =~ "Invitation sent to stranger@example.com"
      assert html =~ "get an email with a link to accept"

      assert_email_sent(fn email ->
        assert email.to == [{"", "stranger@example.com"}]
      end)
    end

    test "student sees email-only pending invite card after sending", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "newparent@example.com"})
        |> render_submit()

      assert html =~ "newparent@example.com"
      assert html =~ "Waiting for them to sign up"
      assert html =~ "Email sent"
    end

    test "student sees error for duplicate pending email invite", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      view
      |> form("form[phx-submit=\"invite\"]", %{email: "dup@example.com"})
      |> render_submit()

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "dup@example.com"})
        |> render_submit()

      assert html =~ "already pending"
    end

    test "student can reject an invitation", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Rejected Parent"})
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      conn = auth_conn(conn, student)
      {:ok, view, _html} = live(conn, ~p"/guardians")

      html = render_click(view, "reject", %{"id" => sg.id})

      assert html =~ "rejected"
    end

    test "student sees error for invalid email format", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: "notvalid"})
        |> render_submit()

      assert html =~ "valid email"
    end

    test "student can revoke an email-only pending invite", %{conn: conn} do
      student = create_user_role(%{role: :student, display_name: "Test Student"})
      conn = auth_conn(conn, student)

      {:ok, view, _html} = live(conn, ~p"/guardians")

      view
      |> form("form[phx-submit=\"invite\"]", %{email: "torevoke@example.com"})
      |> render_submit()

      html = render(view)
      assert html =~ "torevoke@example.com"

      # Find the pending invite id to revoke it
      student_role = Accounts.get_user_role_by_interactor_id(student.interactor_user_id)
      pending = Accounts.list_pending_invites_for_student(student_role.id)
      [invite | _] = pending

      html = render_click(view, "revoke", %{"id" => invite.id})
      # After revoke the invite is gone from pending
      assert html =~ "No pending invitations" or not (html =~ "torevoke@example.com")
    end
  end

  describe "parent additional coverage" do
    test "parent sees Pending Invitations section with no pending when none", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "No Pending Parent"})
      conn = auth_conn(conn, parent)

      {:ok, _view, html} = live(conn, ~p"/guardians")

      assert html =~ "No pending invitations"
    end

    test "parent sees already_linked error when student already linked", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Linked Parent"})
      student = create_user_role(%{role: :student, display_name: "Linked Student"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)
      {:ok, _} = Accounts.accept_guardian_invite(sg.id)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/guardians")

      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: student.email})
        |> render_submit()

      assert html =~ "Already linked"
    end

    test "parent sees already_invited error for duplicate invite", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Dup Parent"})
      student = create_user_role(%{role: :student, display_name: "Dup Student"})

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/guardians")

      # First invite
      view
      |> form("form[phx-submit=\"invite\"]", %{email: student.email})
      |> render_submit()

      # Second invite — duplicate
      html =
        view
        |> form("form[phx-submit=\"invite\"]", %{email: student.email})
        |> render_submit()

      assert html =~ "already pending"
    end

    test "parent can revoke a pending invitation to a student", %{conn: conn} do
      parent = create_user_role(%{role: :parent, display_name: "Revoke Parent"})
      student = create_user_role(%{role: :student, display_name: "Revoke Student"})
      {:ok, sg} = Accounts.invite_guardian(parent.id, student.email, :parent)

      conn = auth_conn(conn, parent)
      {:ok, view, _html} = live(conn, ~p"/guardians")

      html = render_click(view, "revoke", %{"id" => sg.id})
      assert html =~ "revoked" or html =~ "No pending invitations"
    end
  end
end

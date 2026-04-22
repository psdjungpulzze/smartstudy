defmodule FunSheepWeb.GuardianInviteClaimLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.Accounts.StudentGuardian
  alias FunSheep.Repo

  defp create_user_role(attrs) do
    defaults = %{
      interactor_user_id: Ecto.UUID.generate(),
      role: :student,
      email: "user_#{System.unique_integer([:positive])}@test.com",
      display_name: "Test User"
    }

    {:ok, ur} = Accounts.create_user_role(Map.merge(defaults, attrs))
    ur
  end

  defp auth_conn(conn, user_role) do
    role_str = Atom.to_string(user_role.role)

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

  defp pending_email_invite(student) do
    {:ok, sg} =
      Accounts.invite_guardian_by_student(student.id, "grownup@example.com", :parent)

    sg
  end

  test "unknown token shows 'not found' card", %{conn: conn} do
    parent = create_user_role(%{role: :parent, display_name: "Parent"})
    conn = auth_conn(conn, parent)

    {:ok, _view, html} = live(conn, ~p"/guardian-invite/bogus-token")
    assert html =~ "Invitation not found"
  end

  test "expired token shows 'expired' card", %{conn: conn} do
    student = create_user_role(%{role: :student, display_name: "Claire"})
    sg = pending_email_invite(student)

    past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

    {:ok, _} =
      sg
      |> StudentGuardian.changeset(%{invite_token_expires_at: past})
      |> Repo.update()

    parent = create_user_role(%{role: :parent, display_name: "Parent"})
    conn = auth_conn(conn, parent)

    {:ok, _view, html} = live(conn, ~p"/guardian-invite/#{sg.invite_token}")
    assert html =~ "expired"
  end

  test "anonymous visitors are redirected to sign in", %{conn: conn} do
    student = create_user_role(%{role: :student, display_name: "Claire"})
    sg = pending_email_invite(student)

    assert {:error, {:redirect, %{to: to}}} =
             live(conn, ~p"/guardian-invite/#{sg.invite_token}")

    assert String.contains?(to, "login")
  end

  test "parent can claim a valid invite", %{conn: conn} do
    student = create_user_role(%{role: :student, display_name: "Claire"})
    sg = pending_email_invite(student)

    parent =
      create_user_role(%{
        role: :parent,
        display_name: "Grown-up",
        email: "grownup@example.com"
      })

    conn = auth_conn(conn, parent)

    {:ok, view, _html} = live(conn, ~p"/guardian-invite/#{sg.invite_token}")

    html = render_click(view, "claim", %{})

    assert html =~ "all set"

    reloaded = Repo.get!(StudentGuardian, sg.id)
    assert reloaded.guardian_id == parent.id
    assert reloaded.status == :active
    assert reloaded.invite_token == nil
  end

  test "student visitor can't claim a parent invite", %{conn: conn} do
    student = create_user_role(%{role: :student, display_name: "Claire"})
    sg = pending_email_invite(student)

    # A student visiting a parent-only claim link should see the
    # sign-in card (the resolver only surfaces :parent/:teacher roles,
    # so students are treated as unauthenticated for this purpose).
    conn = auth_conn(conn, student)

    {:ok, _view, html} = live(conn, ~p"/guardian-invite/#{sg.invite_token}")
    assert html =~ "Sign in to accept"
  end
end

defmodule FunSheepWeb.UserProfileLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{Social, Repo}
  alias FunSheep.ContentFixtures

  defp make_student(opts \\ []) do
    attrs = Enum.into(opts, %{role: :student})
    ContentFixtures.create_user_role(attrs)
  end

  defp make_school, do: ContentFixtures.create_school()

  defp student_conn(conn, user_role) do
    init_test_session(conn, %{
      dev_user_id: user_role.id,
      dev_user: %{
        "id" => user_role.id,
        "role" => "student",
        "email" => user_role.email,
        "display_name" => user_role.display_name
      }
    })
  end

  defp accepted_invite(inviter, invitee) do
    email = "invite_#{System.unique_integer([:positive])}@test.example"
    {:ok, invite} = Social.create_invite(inviter.id, invitee_email: email)
    Repo.update!(Ecto.Changeset.change(invite, invitee_user_role_id: invitee.id))
    {:ok, _accepted} = Social.accept_invite(invite.invite_token)
  end

  # viewer and subject share a school so can_view_profile? returns true without follows
  defp school_pair do
    school = make_school()
    viewer = make_student(school_id: school.id)
    subject = make_student(school_id: school.id)
    {viewer, subject}
  end

  describe "UserProfileLive — flock tree section" do
    test "shows flock tree section when subject has accepted invites", %{conn: conn} do
      {viewer, subject} = school_pair()
      invitee = make_student()
      accepted_invite(subject, invitee)

      conn = student_conn(conn, viewer)
      {:ok, _lv, html} = live(conn, ~p"/social/profile/#{subject.id}")

      assert html =~ "Flock Tree"
      assert html =~ "Brought to the flock"
      assert html =~ invitee.display_name
    end

    test "hides flock tree section when subject has no invite history", %{conn: conn} do
      {viewer, subject} = school_pair()

      conn = student_conn(conn, viewer)
      {:ok, _lv, html} = live(conn, ~p"/social/profile/#{subject.id}")

      refute html =~ "Flock Tree"
    end

    test "shows who invited the subject", %{conn: conn} do
      school = make_school()
      inviter = make_student()
      subject = make_student(school_id: school.id)
      viewer = make_student(school_id: school.id)

      accepted_invite(inviter, subject)

      conn = student_conn(conn, viewer)
      {:ok, _lv, html} = live(conn, ~p"/social/profile/#{subject.id}")

      assert html =~ "Invited by"
      assert html =~ inviter.display_name
    end

    test "redirects to leaderboard if viewer cannot see profile", %{conn: conn} do
      viewer = make_student()
      stranger = make_student()

      conn = student_conn(conn, viewer)

      assert {:error, {:redirect, %{to: "/leaderboard"}}} =
               live(conn, ~p"/social/profile/#{stranger.id}")
    end
  end

  describe "UserProfileLive — follow/unfollow actions" do
    test "follow button appears when viewer does not follow subject yet", %{conn: conn} do
      {viewer, subject} = school_pair()

      conn = student_conn(conn, viewer)
      {:ok, _lv, html} = live(conn, ~p"/social/profile/#{subject.id}")

      assert html =~ "+ Follow"
    end

    test "follow action transitions to Following state", %{conn: conn} do
      {viewer, subject} = school_pair()

      conn = student_conn(conn, viewer)
      {:ok, lv, _html} = live(conn, ~p"/social/profile/#{subject.id}")

      html = lv |> element("button[phx-click=follow]") |> render_click()
      assert html =~ "Following" or html =~ "Friends"
    end

    test "unfollow action transitions back to Follow state", %{conn: conn} do
      {viewer, subject} = school_pair()
      Social.follow(viewer.id, subject.id)
      Social.follow(subject.id, viewer.id)

      conn = student_conn(conn, viewer)
      {:ok, lv, html} = live(conn, ~p"/social/profile/#{subject.id}")

      assert html =~ "Friends" or html =~ "Following"

      html = lv |> element("button[phx-click=unfollow]") |> render_click()
      assert html =~ "+ Follow"
    end
  end
end

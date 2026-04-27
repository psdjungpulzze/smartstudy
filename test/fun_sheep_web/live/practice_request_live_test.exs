defmodule FunSheepWeb.PracticeRequestLiveTest do
  @moduledoc """
  Tests for the practice request LiveComponents:
    - PracticeRequestLive.ParentCardComponent (via /parent)

  These LiveComponents are exercised through the pages that embed them.
  The ParentCardComponent:
    - update/2         — driven by parent dashboard mount
    - assign_requests/2 (parent_id: nil)  — when user_role is nil
    - assign_requests/2 (parent_id: uuid) — with a real parent
    - handle_event("decline_request")     — via the Decline button
    - render/1                            — rendered through parent dashboard
  """

  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.Accounts
  alias FunSheep.PracticeRequests

  # ---------------------------------------------------------------------------
  # Helpers — match the pattern from parent_dashboard_live_test.exs
  # ---------------------------------------------------------------------------

  defp make_user_role(role \\ :parent) do
    {:ok, ur} =
      Accounts.create_user_role(%{
        interactor_user_id: Ecto.UUID.generate(),
        role: role,
        email: "user#{System.unique_integer([:positive])}@test.com",
        display_name: "Test #{role}"
      })

    ur
  end

  defp auth_conn(conn, user_role) do
    conn
    |> init_test_session(%{
      dev_user_id: user_role.interactor_user_id,
      dev_user: %{
        "id" => user_role.interactor_user_id,
        "interactor_user_id" => user_role.interactor_user_id,
        "role" => to_string(user_role.role),
        "email" => user_role.email,
        "display_name" => user_role.display_name
      }
    })
  end

  defp link_guardian(parent, student) do
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

  # ---------------------------------------------------------------------------
  # ParentCardComponent — tested through /parent
  # ---------------------------------------------------------------------------

  describe "ParentCardComponent — no pending requests" do
    test "parent dashboard mounts and renders for a parent user", %{conn: conn} do
      parent = make_user_role(:parent)
      {:ok, _view, html} = live(auth_conn(conn, parent), ~p"/parent")

      # Page renders successfully; greeting appears
      assert html =~ "Parent Dashboard"
    end

    test "component mounts with empty request list — no request card shown", %{conn: conn} do
      parent = make_user_role(:parent)
      {:ok, _view, html} = live(auth_conn(conn, parent), ~p"/parent")

      # The parent_request_card renders nothing when requests == [] (the ~H"" branch)
      # So the Decline/Unlock buttons are absent
      refute html =~ "Not right now"
    end
  end

  describe "ParentCardComponent — with a pending request" do
    test "parent_request_card shows request when a pending request exists", %{conn: conn} do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, _request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :upcoming_test})

      {:ok, _view, html} = live(auth_conn(conn, parent), ~p"/parent")

      # The parent_request_card renders with the student's name and decline button
      assert html =~ "Your child asked for more practice"
      assert html =~ "Not right now"
    end

    test "decline_request event via 'Not right now' button removes the request", %{conn: conn} do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :upcoming_test})

      {:ok, view, _html} = live(auth_conn(conn, parent), ~p"/parent")

      # Click the "Not right now" / Decline button in the rendered component
      view
      |> element("button[phx-click='decline_request']")
      |> render_click(%{"id" => request.id})

      # After decline the request is no longer pending
      assert PracticeRequests.list_pending_for_guardian(parent.id) == []

      # The decline card should no longer appear in the re-rendered HTML
      html = render(view)
      refute html =~ "Not right now"
    end
  end

  describe "ParentCardComponent — assign_requests nil branch (user_role not found)" do
    test "parent dashboard renders when interactor_user_id has no DB user_role", %{conn: conn} do
      # A parent with an interactor_user_id that has no matching user_role row →
      # get_user_role_by_interactor_id returns nil → @user_role assign is nil →
      # the :if={@user_role} guard suppresses the component → no crash.
      unknown_itr_id = Ecto.UUID.generate()

      conn_unknown =
        conn
        |> init_test_session(%{
          dev_user_id: unknown_itr_id,
          dev_user: %{
            "id" => unknown_itr_id,
            "interactor_user_id" => unknown_itr_id,
            "role" => "parent",
            "email" => "ghost@test.com",
            "display_name" => "Ghost Parent"
          }
        })

      {:ok, _view, html} = live(conn_unknown, ~p"/parent")
      # Page renders; component is suppressed (no user_role)
      assert html =~ "Parent Dashboard"
      # No requests were loaded
      refute html =~ "Not right now"
    end
  end

  # ---------------------------------------------------------------------------
  # PracticeRequests context — covers the logic ParentCardComponent relies on
  # ---------------------------------------------------------------------------

  describe "PracticeRequests context" do
    test "list_pending_for_guardian returns empty list for fresh parent" do
      parent = make_user_role(:parent)
      assert PracticeRequests.list_pending_for_guardian(parent.id) == []
    end

    test "list_pending_for_guardian returns pending requests for linked parent" do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, _request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :weak_topic})

      requests = PracticeRequests.list_pending_for_guardian(parent.id)
      assert length(requests) == 1
      assert hd(requests).status in [:pending, :viewed]
    end

    test "decline marks request as declined and removes from pending list" do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :upcoming_test})

      assert {:ok, declined} = PracticeRequests.decline(request.id, nil)
      assert declined.status == :declined
      assert PracticeRequests.list_pending_for_guardian(parent.id) == []
    end

    test "view marks request as :viewed" do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

      assert {:ok, viewed} = PracticeRequests.view(request.id)
      assert viewed.status == :viewed
    end

    test "view is idempotent on an already-viewed request" do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, request} =
        PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

      {:ok, _} = PracticeRequests.view(request.id)
      {:ok, viewed_again} = PracticeRequests.view(request.id)
      assert viewed_again.status == :viewed
    end

    test "create enforces one pending request per student" do
      parent = make_user_role(:parent)
      student = make_user_role(:student)
      :ok = link_guardian(parent, student)

      {:ok, _} = PracticeRequests.create(student.id, parent.id, %{reason_code: :upcoming_test})

      assert {:error, :already_pending} =
               PracticeRequests.create(student.id, parent.id, %{reason_code: :weak_topic})
    end
  end
end

defmodule FunSheepWeb.FlowASubscriptionTest do
  @moduledoc """
  Covers the `/subscription` surfaces affected by Flow A:
    * Teacher guard renders the free-for-educators message (§6.3, §8.5)
    * `?request=<id>` loads the request and marks it :viewed (§4.7)
  """

  use FunSheepWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FunSheep.{Accounts, PracticeRequests}

  defp user_conn(conn, role) do
    {:ok, user} =
      Accounts.create_user_role(%{
        interactor_user_id: "#{role}_#{System.unique_integer([:positive])}",
        role: role,
        email: "#{role}_#{System.unique_integer([:positive])}@t.com",
        display_name: "#{role}"
      })

    conn =
      init_test_session(conn, %{
        dev_user_id: user.id,
        dev_user: %{
          "id" => user.id,
          "user_role_id" => user.id,
          "interactor_user_id" => user.interactor_user_id,
          "role" => Atom.to_string(role),
          "email" => user.email,
          "display_name" => user.display_name
        }
      })

    {conn, user}
  end

  describe "teacher guard (§6.3, §8.5)" do
    test "teachers see the free-for-educators page, not the plan picker", %{conn: conn} do
      {conn, _teacher} = user_conn(conn, :teacher)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      assert html =~ "free for educators"
      assert html =~ "Teachers don"
    end

    test "students still see the plan picker", %{conn: conn} do
      {conn, _student} = user_conn(conn, :student)
      {:ok, _view, html} = live(conn, ~p"/subscription")

      refute html =~ "Teachers don't need a subscription"
    end
  end

  describe "accept-link handling (§4.7)" do
    test "loading /subscription?request=<id> marks the request :viewed and surfaces the student name",
         %{conn: conn} do
      {conn, parent} = user_conn(conn, :parent)

      {:ok, student} =
        Accounts.create_user_role(%{
          interactor_user_id: "student_#{System.unique_integer([:positive])}",
          role: :student,
          email: "kid@t.com",
          display_name: "Lia"
        })

      {:ok, _} =
        Accounts.create_student_guardian(%{
          guardian_id: parent.id,
          student_id: student.id,
          relationship_type: :parent,
          status: :active,
          invited_at: DateTime.utc_now() |> DateTime.truncate(:second),
          accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, req} = PracticeRequests.create(student.id, parent.id, %{reason_code: :streak})

      {:ok, _view, html} = live(conn, ~p"/subscription?request=#{req.id}")

      # Phoenix HTML-escapes the apostrophe, so match the un-apostrophized segment.
      assert html =~ "unlocking unlimited practice for"
      assert html =~ "Lia"

      # Viewed stamp landed
      updated = FunSheep.Repo.get!(FunSheep.PracticeRequests.Request, req.id)
      assert updated.status == :viewed
      assert not is_nil(updated.viewed_at)
    end
  end
end

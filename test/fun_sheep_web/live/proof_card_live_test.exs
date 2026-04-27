defmodule FunSheepWeb.ProofCardLiveTest do
  use FunSheepWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FunSheep.{ContentFixtures, Repo}
  alias FunSheep.Engagement.ProofCard

  defp create_proof_card(user_role, course, card_type, metrics \\ %{}) do
    token = Ecto.UUID.generate()

    {:ok, card} =
      %ProofCard{}
      |> ProofCard.changeset(%{
        card_type: card_type,
        title: "Test Achievement",
        metrics: metrics,
        share_token: token,
        user_role_id: user_role.id,
        course_id: course.id
      })
      |> Repo.insert()

    card
  end

  setup do
    user_role = ContentFixtures.create_user_role()
    course = ContentFixtures.create_course(%{name: "Biology 101"})
    %{user_role: user_role, course: course}
  end

  describe "not found state" do
    test "shows not-found message for invalid token", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/share/progress/nonexistent-token-xyz")

      assert html =~ "Card Not Found"
    end
  end

  describe "readiness_jump card" do
    test "renders readiness jump card", %{conn: conn, user_role: ur, course: c} do
      card = create_proof_card(ur, c, "readiness_jump", %{"from" => 40, "to" => 75})

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Readiness Achievement"
      assert html =~ "40%"
      assert html =~ "75%"
    end
  end

  describe "streak_milestone card" do
    test "renders streak milestone card", %{conn: conn, user_role: ur, course: c} do
      card = create_proof_card(ur, c, "streak_milestone", %{"days" => 14})

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Study Session" or html =~ "14-Day" or html =~ "Streak"
    end
  end

  describe "weekly_rank card" do
    test "renders weekly rank card for rank 1", %{conn: conn, user_role: ur, course: c} do
      card = create_proof_card(ur, c, "weekly_rank", %{"rank" => 1})

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Weekly Ranking" or html =~ "#1"
    end
  end

  describe "session_receipt card" do
    test "renders session receipt card", %{conn: conn, user_role: ur, course: c} do
      card = create_proof_card(ur, c, "session_receipt", %{"questions" => 20, "accuracy" => 85})

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Study Session" or html =~ "20 questions" or html =~ "85%"
    end
  end

  describe "generic card" do
    test "renders test_complete card with title (falls through to generic render)", %{
      conn: conn,
      user_role: ur,
      course: c
    } do
      {:ok, card} =
        %ProofCard{}
        |> ProofCard.changeset(%{
          card_type: "test_complete",
          title: "Special Badge",
          metrics: %{},
          share_token: Ecto.UUID.generate(),
          user_role_id: ur.id,
          course_id: c.id
        })
        |> Repo.insert()

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Special Badge"
    end
  end

  describe "percentile badge" do
    test "shows percentile badge when present in metrics", %{conn: conn, user_role: ur, course: c} do
      card =
        create_proof_card(ur, c, "readiness_jump", %{
          "from" => 50,
          "to" => 80,
          "percentile" => 10
        })

      {:ok, _view, html} = live(conn, ~p"/share/progress/#{card.share_token}")

      assert html =~ "Top 10% of students"
    end
  end
end

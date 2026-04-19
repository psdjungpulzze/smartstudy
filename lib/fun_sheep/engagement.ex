defmodule FunSheep.Engagement do
  @moduledoc """
  The Engagement context — facade for all engagement features.

  Coordinates spaced repetition, daily challenges, study sessions,
  proof cards, and time-gated bonuses.
  """

  import Ecto.Query, warn: false
  alias FunSheep.Repo

  alias FunSheep.Engagement.{
    ProofCard,
    SpacedRepetition,
    StudySessions
  }

  ## ── Proof Cards ──────────────────────────────────────────────────────────

  @doc "Creates a proof card for a readiness jump."
  def create_readiness_proof_card(user_role_id, attrs) do
    %ProofCard{}
    |> ProofCard.changeset(
      Map.merge(attrs, %{
        card_type: "readiness_jump",
        share_token: ProofCard.generate_token(),
        user_role_id: user_role_id
      })
    )
    |> Repo.insert()
  end

  @doc "Creates a proof card for a streak milestone."
  def create_streak_proof_card(user_role_id, streak_days) do
    %ProofCard{}
    |> ProofCard.changeset(%{
      card_type: "streak_milestone",
      title: "#{streak_days}-Day Study Streak!",
      metrics: %{streak_days: streak_days},
      share_token: ProofCard.generate_token(),
      user_role_id: user_role_id
    })
    |> Repo.insert()
  end

  @doc "Creates a proof card for a session receipt."
  def create_session_proof_card(user_role_id, session_data) do
    %ProofCard{}
    |> ProofCard.changeset(%{
      card_type: "session_receipt",
      title: "Study Session Complete",
      metrics: session_data,
      share_token: ProofCard.generate_token(),
      user_role_id: user_role_id,
      course_id: session_data[:course_id]
    })
    |> Repo.insert()
  end

  @doc "Gets a proof card by its share token."
  def get_proof_card_by_token(token) do
    ProofCard
    |> Repo.get_by(share_token: token)
    |> Repo.preload([:user_role, :course])
  end

  @doc "Lists proof cards for a user."
  def list_proof_cards(user_role_id) do
    from(pc in ProofCard,
      where: pc.user_role_id == ^user_role_id,
      order_by: [desc: pc.inserted_at],
      preload: [:course]
    )
    |> Repo.all()
  end

  ## ── Post-Session Hooks ────────────────────────────────────────────────

  @doc """
  Called after any study session completes. Handles:
  1. Creating review cards from wrong answers (spaced repetition)
  2. Checking for proof-card-worthy milestones
  3. Recording activity for streak tracking
  """
  def after_session(user_role_id, course_id, _session_data \\ %{}) do
    # Create review cards from wrong answers
    SpacedRepetition.auto_create_from_wrong_answers(user_role_id, course_id)

    # Record activity for streak
    FunSheep.Gamification.record_activity(user_role_id)

    # Check streak achievements
    FunSheep.Gamification.check_streak_achievements(user_role_id)

    :ok
  end

  ## ── Engagement Summary (for admin/analytics) ───────────────────────────

  @doc "Returns a comprehensive engagement summary for a user."
  def user_engagement_summary(user_role_id) do
    review_stats = SpacedRepetition.review_stats(user_role_id)
    daily_summary = StudySessions.daily_summary(user_role_id)
    gamification = FunSheep.Gamification.dashboard_summary(user_role_id)

    %{
      review: review_stats,
      daily: daily_summary,
      gamification: gamification
    }
  end
end

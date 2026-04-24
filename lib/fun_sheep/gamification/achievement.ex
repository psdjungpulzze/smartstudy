defmodule FunSheep.Gamification.Achievement do
  @moduledoc """
  Schema for user achievements/badges.

  Tracks earned badges like Golden Fleece (100% readiness),
  streak milestones, and topic mastery.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @achievement_types ~w(
    golden_fleece
    first_assessment
    first_practice
    streak_3
    streak_7
    streak_14
    streak_30
    streak_100
    topic_mastery
    chapter_mastery
    speed_demon
    perfect_score
    night_owl
    early_bird
    comeback_kid
    first_follow
    first_follower
    flock_starter
    shepherd
    lead_shepherd
    flock_builder
    study_buddy
    mutual_10
  )

  schema "achievements" do
    field :achievement_type, :string
    field :metadata, :map, default: %{}
    field :earned_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(achievement, attrs) do
    achievement
    |> cast(attrs, [:achievement_type, :metadata, :earned_at, :user_role_id])
    |> validate_required([:achievement_type, :earned_at, :user_role_id])
    |> validate_inclusion(:achievement_type, @achievement_types)
    |> unique_constraint([:user_role_id, :achievement_type])
    |> foreign_key_constraint(:user_role_id)
  end

  @doc "Returns display info for an achievement type."
  def display_info(type) do
    case type do
      "golden_fleece" ->
        %{name: "Golden Fleece", emoji: "✨", description: "Reached 100% readiness on a test"}

      "first_assessment" ->
        %{name: "First Steps", emoji: "🐣", description: "Completed your first assessment"}

      "first_practice" ->
        %{
          name: "Practice Makes Perfect",
          emoji: "🏋️",
          description: "Completed your first practice session"
        }

      "streak_3" ->
        %{name: "Getting Warm", emoji: "🔥", description: "3-day study streak"}

      "streak_7" ->
        %{name: "On Fire", emoji: "🔥", description: "7-day study streak"}

      "streak_14" ->
        %{name: "Unstoppable", emoji: "💪", description: "14-day study streak"}

      "streak_30" ->
        %{name: "Dedicated", emoji: "🏆", description: "30-day study streak"}

      "streak_100" ->
        %{name: "Legend", emoji: "👑", description: "100-day study streak"}

      "topic_mastery" ->
        %{name: "Topic Master", emoji: "⭐", description: "Scored 90%+ on a topic"}

      "chapter_mastery" ->
        %{
          name: "Chapter Champion",
          emoji: "🎖️",
          description: "Scored 90%+ on all topics in a chapter"
        }

      "speed_demon" ->
        %{name: "Speed Demon", emoji: "⚡", description: "Completed a quick test in record time"}

      "perfect_score" ->
        %{name: "Flawless", emoji: "💯", description: "Perfect score on an assessment"}

      "night_owl" ->
        %{name: "Night Owl", emoji: "🦉", description: "Studied past midnight"}

      "early_bird" ->
        %{name: "Early Bird", emoji: "🌅", description: "Studied before 6 AM"}

      "comeback_kid" ->
        %{name: "Comeback Kid", emoji: "🐑", description: "Recovered a broken streak"}

      "first_follow" ->
        %{name: "Friendly Sheep", emoji: "🐑", description: "Followed your first classmate"}

      "first_follower" ->
        %{name: "Flock Magnet", emoji: "🐏", description: "Someone followed you!"}

      "flock_starter" ->
        %{name: "Flock Starter", emoji: "🌱", description: "Gained 5 followers"}

      "shepherd" ->
        %{name: "Shepherd", emoji: "🐕", description: "Invited 5 students who joined"}

      "lead_shepherd" ->
        %{name: "Lead Shepherd", emoji: "🏅", description: "Invited 10 students who joined"}

      "flock_builder" ->
        %{name: "Flock Builder", emoji: "🌟", description: "Invited 20 students who joined"}

      "study_buddy" ->
        %{name: "Study Buddy", emoji: "🤝", description: "Completed a shared course together"}

      "mutual_10" ->
        %{name: "Social Butterfly", emoji: "♥", description: "10 mutual follows — true friends!"}

      _ ->
        %{name: type, emoji: "🏅", description: "Achievement unlocked"}
    end
  end
end

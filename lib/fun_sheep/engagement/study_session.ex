defmodule FunSheep.Engagement.StudySession do
  @moduledoc """
  Schema for tracking individual study sessions.

  Used for study receipts, time-gated FP bonuses, and parent activity signals.
  Each session records what was studied, how well, and when.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @session_types ~w(review practice assessment quick_test daily_challenge just_this exam_simulation)
  @time_windows ~w(morning afternoon evening night)

  schema "study_sessions" do
    field :session_type, :string
    field :questions_attempted, :integer, default: 0
    field :questions_correct, :integer, default: 0
    field :duration_seconds, :integer, default: 0
    field :xp_earned, :integer, default: 0
    field :readiness_before, :float
    field :readiness_after, :float
    field :topics_covered, {:array, :string}, default: []
    field :time_window, :string
    field :completed_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :session_type,
      :questions_attempted,
      :questions_correct,
      :duration_seconds,
      :xp_earned,
      :readiness_before,
      :readiness_after,
      :topics_covered,
      :time_window,
      :completed_at,
      :metadata,
      :user_role_id,
      :course_id
    ])
    |> validate_required([:session_type, :user_role_id])
    |> validate_inclusion(:session_type, @session_types)
    |> validate_inclusion(:time_window, @time_windows ++ [nil])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end

  @doc "Determines the current time window based on hour (UTC)."
  def current_time_window do
    hour = DateTime.utc_now().hour

    cond do
      hour >= 6 and hour < 12 -> "morning"
      hour >= 12 and hour < 17 -> "afternoon"
      hour >= 17 and hour < 22 -> "evening"
      true -> "night"
    end
  end
end

defmodule FunSheep.Engagement.DailyChallengeAttempt do
  @moduledoc """
  Schema for a user's attempt at a daily challenge.

  Each user can only attempt each daily challenge once.
  Tracks individual answers, total score, and completion time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "daily_challenge_attempts" do
    field :answers, :map, default: %{}
    field :score, :integer, default: 0
    field :total_time_ms, :integer, default: 0
    field :completed_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :daily_challenge, FunSheep.Engagement.DailyChallenge

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :answers,
      :score,
      :total_time_ms,
      :completed_at,
      :user_role_id,
      :daily_challenge_id
    ])
    |> validate_required([:user_role_id, :daily_challenge_id])
    |> validate_number(:score, greater_than_or_equal_to: 0)
    |> validate_number(:total_time_ms, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_role_id, :daily_challenge_id])
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:daily_challenge_id)
  end
end

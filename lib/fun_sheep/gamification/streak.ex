defmodule FunSheep.Gamification.Streak do
  @moduledoc """
  Schema for user study streaks.

  Tracks consecutive days of study activity. The wool_level
  visualizes streak length on the sheep mascot (higher = fluffier).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "streaks" do
    field :current_streak, :integer, default: 0
    field :longest_streak, :integer, default: 0
    field :last_activity_date, :date
    field :streak_frozen_until, :date
    field :wool_level, :integer, default: 0

    # Freeze tracking — added by 20260424430000_add_streak_fields migration.
    # freeze_count: lifetime number of freezes the user has activated.
    # freeze_used_at: date of the most recent freeze activation.
    field :freeze_count, :integer, default: 0
    field :freeze_used_at, :date

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(streak, attrs) do
    streak
    |> cast(attrs, [
      :current_streak,
      :longest_streak,
      :last_activity_date,
      :streak_frozen_until,
      :wool_level,
      :freeze_count,
      :freeze_used_at,
      :user_role_id
    ])
    |> validate_required([:user_role_id])
    |> validate_number(:current_streak, greater_than_or_equal_to: 0)
    |> validate_number(:longest_streak, greater_than_or_equal_to: 0)
    |> validate_number(:wool_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:freeze_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:user_role_id)
    |> foreign_key_constraint(:user_role_id)
  end
end

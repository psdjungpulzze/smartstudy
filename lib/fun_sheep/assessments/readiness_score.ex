defmodule FunSheep.Assessments.ReadinessScore do
  @moduledoc """
  Schema for test readiness scores.

  Stores aggregate and per-chapter/topic scores for a student
  relative to a scheduled test.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "readiness_scores" do
    field :chapter_scores, :map
    field :topic_scores, :map
    field :aggregate_score, :float
    field :calculated_at, :utc_datetime

    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :test_schedule, FunSheep.Assessments.TestSchedule

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(readiness_score, attrs) do
    readiness_score
    |> cast(attrs, [
      :chapter_scores,
      :topic_scores,
      :aggregate_score,
      :calculated_at,
      :user_role_id,
      :test_schedule_id
    ])
    |> validate_required([
      :chapter_scores,
      :topic_scores,
      :aggregate_score,
      :calculated_at,
      :user_role_id,
      :test_schedule_id
    ])
    |> validate_number(:aggregate_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:test_schedule_id)
  end
end

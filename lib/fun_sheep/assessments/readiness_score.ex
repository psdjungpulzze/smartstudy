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
    field :skill_scores, :map, default: %{}
    field :aggregate_score, :float
    field :calculated_at, :utc_datetime

    # Virtual fields — computed live, never persisted.
    # coverage_pct: % of in-scope sections that have ≥1 student-visible question.
    # empty_section_ids: section IDs with 0 questions (student cannot practice these).
    # full_test_readiness: aggregate_score × (coverage_pct / 100), a conservative
    #   estimate of true preparedness when some topics lack questions.
    field :coverage_pct, :float, virtual: true, default: 100.0
    field :empty_section_ids, {:array, :string}, virtual: true, default: []
    field :full_test_readiness, :float, virtual: true, default: 0.0

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
      :skill_scores,
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

defmodule FunSheep.Questions.QuestionStats do
  @moduledoc """
  Aggregate statistics for a question across all students.

  Tracks attempt difficulty and community flags. Positive quality signals
  (attempts, completions) are handled by the engagement scoring layer.
  quality_score here is a penalty-only value: 0.0 is clean, negative means
  students have flagged problems with this question.

  Formula: quality_score = -(flag_count × 5.0)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @flag_weight 5.0

  schema "question_stats" do
    field :total_attempts, :integer, default: 0
    field :correct_attempts, :integer, default: 0
    field :difficulty_score, :float, default: 0.5
    field :avg_time_seconds, :float, default: 0.0

    field :flag_count, :integer, default: 0
    field :quality_score, :float, default: 0.0

    belongs_to :question, FunSheep.Questions.Question

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(stats, attrs) do
    stats
    |> cast(attrs, [
      :total_attempts,
      :correct_attempts,
      :difficulty_score,
      :avg_time_seconds,
      :flag_count,
      :quality_score,
      :question_id
    ])
    |> validate_required([:question_id])
    |> validate_number(:total_attempts, greater_than_or_equal_to: 0)
    |> validate_number(:correct_attempts, greater_than_or_equal_to: 0)
    |> validate_number(:difficulty_score,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
    |> validate_number(:flag_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:question_id)
  end

  @doc """
  Computes difficulty_score from attempt counts.
  Score = 1 - (correct / total). Higher = harder.
  With Bayesian smoothing: assume 2 virtual attempts at 50% to avoid extremes on low data.
  """
  def compute_difficulty(correct, total) when total > 0 do
    smoothed_correct = correct + 1
    smoothed_total = total + 2
    Float.round(1.0 - smoothed_correct / smoothed_total, 4)
  end

  def compute_difficulty(_correct, _total), do: 0.5

  @doc """
  Computes quality_score from flag count. Returns 0.0 or negative — the
  positive ranking dimension is handled by engagement metrics (attempts,
  completions), not community votes.
  """
  def compute_quality(flags) do
    Float.round(-flags * @flag_weight, 2)
  end
end

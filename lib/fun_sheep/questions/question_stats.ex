defmodule FunSheep.Questions.QuestionStats do
  @moduledoc """
  Aggregate statistics for a question across all students.

  Tracks attempts, difficulty, and community feedback signals.

  quality_score formula:
    (like_count × 1.0) - (dislike_count × 3.0) - (flag_count × 5.0)

  Dislikes are weighted 3× likes because explicit negative feedback requires
  deliberate action and is a stronger quality signal than a passive like.
  Flags (incorrect/unclear content) are weighted 5× — they indicate a specific
  content defect that hurts every student who sees that question.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @like_weight 1.0
  @dislike_weight 3.0
  @flag_weight 5.0

  schema "question_stats" do
    field :total_attempts, :integer, default: 0
    field :correct_attempts, :integer, default: 0
    field :difficulty_score, :float, default: 0.5
    field :avg_time_seconds, :float, default: 0.0

    field :like_count, :integer, default: 0
    field :dislike_count, :integer, default: 0
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
      :like_count,
      :dislike_count,
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
    |> validate_number(:like_count, greater_than_or_equal_to: 0)
    |> validate_number(:dislike_count, greater_than_or_equal_to: 0)
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
  Computes quality_score from community feedback counts.

  Dislikes are weighted #{@dislike_weight}× and flags #{@flag_weight}× because they represent
  deliberate negative signals — a user who goes out of their way to say
  a question is bad is providing stronger information than a passive like.
  """
  def compute_quality(likes, dislikes, flags) do
    Float.round(
      likes * @like_weight - dislikes * @dislike_weight - flags * @flag_weight,
      2
    )
  end
end
